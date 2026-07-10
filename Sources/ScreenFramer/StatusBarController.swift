import AppKit
import ScreenFramerCore

/// Menüleisten-Icon und Menü; hält den App-Zustand und verdrahtet
/// VirtualDisplayController, CaptureEngine und MirrorWindowController.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let captureEngine = CaptureEngine()
    private let virtualDisplayController = VirtualDisplayController()
    private var mirrorWindowController: MirrorWindowController?
    private var frameOverlayController: CropFrameOverlayController?

    /// Monitor, auf dessen Menüleiste zuletzt geklickt wurde (beim Menü-Öffnen ermittelt)
    private var clickedDisplayID: CGDirectDisplayID?
    /// Monitor, der gerade übertragen wird
    private var activeDisplayID: CGDirectDisplayID?
    private let configStore = ConfigStore()
    private var configurations: [CropConfiguration] = []
    private var activeConfiguration: CropConfiguration?
    private var isRunning = false
    private var isStarting = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.center.inset.filled",
            accessibilityDescription: "Screen Framer")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        do {
            configurations = try configStore.loadCreatingIfMissing()
        } catch {
            // Launch nicht blockieren — Alert erst nach dem App-Start
            DispatchQueue.main.async { [weak self] in
                self?.showError(
                    error, title: "Konfiguration konnte nicht geladen werden")
            }
        }
    }

    // Menü bei jedem Öffnen neu aufbauen: Der Zielmonitor ist der Bildschirm,
    // auf dessen Menüleiste geklickt wurde (automatische Erkennung).
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let clickedScreen = statusItem.button?.window?.screen ?? NSScreen.main
        clickedDisplayID = clickedScreen?.displayID
        // Der virtuelle Bildschirm ist nie Capture-Quelle (Endlosschleife)
        let clickedIsVirtual =
            clickedDisplayID != nil
            && clickedDisplayID == virtualDisplayController.displayID

        if let clickedScreen {
            let infoItem = NSMenuItem(
                title: "Monitor: \(clickedScreen.localizedName)", action: nil,
                keyEquivalent: "")
            menu.addItem(infoItem)
            menu.addItem(.separator())
        }

        if configurations.isEmpty {
            let emptyItem = NSMenuItem(
                title: "Keine gültigen Konfigurationen", action: nil,
                keyEquivalent: "")
            menu.addItem(emptyItem)
        }
        // Konfigurationseinträge als eigene Views (Icon rechtsbündig).
        // Alle bekommen dieselbe Breite = die des breitesten Eintrags, damit
        // die Konfig-Zeilen die breitesten im Menü sind und ihre Icons die
        // rechte Menükante definieren (ein NSMenuItem-Titel kann das nicht).
        let displaySize = clickedScreen?.frame.size ?? CGSize(width: 16, height: 9)
        let isEnabled = clickedDisplayID != nil && !clickedIsVirtual && !isStarting
        let items = configurations.map { configuration -> NSMenuItem in
            let item = NSMenuItem(
                title: configuration.name, action: nil, keyEquivalent: "")
            item.representedObject = configuration.name
            return item
        }
        let views = configurations.map { configuration in
            ConfigurationMenuItemView(
                configuration: configuration, displaySize: displaySize,
                isActive: isRunning && configuration.name == activeConfiguration?.name,
                isEnabled: isEnabled, width: 0,
                onSelect: { [weak self] in self?.selectConfiguration(named: configuration.name) })
        }
        let rowWidth = views.map { $0.fittingWidth() }.max() ?? 0
        for (item, view) in zip(items, views) {
            view.setFrameSize(NSSize(width: rowWidth, height: view.frame.height))
            view.autoresizingMask = [.width]
            item.view = view
            menu.addItem(item)
        }

        if isRunning {
            menu.addItem(.separator())
            let stopItem = NSMenuItem(
                title: "Übertragung stoppen", action: #selector(stopCapture),
                keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        }

        menu.addItem(.separator())
        let openItem = NSMenuItem(
            title: "Konfigurationsdatei öffnen",
            action: #selector(openConfigFile), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        let reloadItem = NSMenuItem(
            title: "Konfiguration neu laden",
            action: #selector(reloadConfig), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Beenden", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // Klick auf eine Konfiguration: startet die Übertragung für den Monitor,
    // auf dem das Menü geöffnet wurde — bzw. wechselt nur die Konfiguration,
    // wenn genau dieser Monitor bereits übertragen wird.
    private func selectConfiguration(named name: String) {
        guard let newConfiguration = configurations.first(where: { $0.name == name }),
              let displayID = clickedDisplayID,
              displayID != virtualDisplayController.displayID,
              !isStarting else { return }

        if isRunning, displayID == activeDisplayID {
            guard newConfiguration != activeConfiguration else { return }
            switchConfiguration(to: newConfiguration, on: displayID)
            return
        }

        activeConfiguration = newConfiguration
        startCapture(on: displayID)
    }

    /// Wechselt die Konfiguration einer laufenden Übertragung. Bleibt die
    /// Pixelgröße des Ausschnitts gleich, wird nur der Stream umkonfiguriert;
    /// sonst muss der virtuelle Bildschirm neu erzeugt werden (Neustart).
    private func switchConfiguration(
        to newConfiguration: CropConfiguration, on displayID: CGDirectDisplayID
    ) {
        let previous = activeConfiguration
        activeConfiguration = newConfiguration
        guard let previous,
              cropPixelSize(for: displayID, configuration: previous)
                  == cropPixelSize(for: displayID, configuration: newConfiguration)
        else {
            startCapture(on: displayID)
            return
        }
        Task { @MainActor in
            do {
                try await self.captureEngine.update(configuration: newConfiguration)
                // Zwischenzeitliches Teardown (z. B. Stream-Fehler): kein
                // Overlay für eine beendete Übertragung wiederbeleben
                guard self.isRunning, self.activeDisplayID == displayID else { return }
                self.showFrameOverlay(for: displayID)
            } catch {
                self.activeConfiguration = previous
                self.showError(error, title: "Konfigurationswechsel fehlgeschlagen")
            }
        }
    }

    private func startCapture(on displayID: CGDirectDisplayID) {
        guard !isStarting, let configuration = activeConfiguration else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            showPermissionAlert()
            return
        }
        guard let pixelSize = cropPixelSize(for: displayID, configuration: configuration) else {
            showError(
                CaptureError.displayNotFound,
                title: "Übertragung konnte nicht gestartet werden")
            return
        }

        isStarting = true
        Task { @MainActor in
            // Laufende Übertragung (z. B. auf dem anderen Monitor) zuerst beenden
            if self.isRunning {
                await self.teardown()
            }

            do {
                let screen = try await self.virtualDisplayController.create(
                    name: "Screen Framer", pixelSize: pixelSize)
                let windowController = MirrorWindowController(screen: screen)
                self.captureEngine.onFrame = { [weak windowController] buffer in
                    windowController?.enqueue(buffer)
                }
                self.captureEngine.onStopped = { [weak self] error in
                    guard let self else { return }
                    Task { @MainActor in
                        await self.teardown(stopEngine: false)
                        if let error { self.showError(error) }
                    }
                }
                try await self.captureEngine.start(
                    displayID: displayID, configuration: configuration)
                windowController.window?.orderFrontRegardless()
                self.mirrorWindowController = windowController
                self.activeDisplayID = displayID
                self.isRunning = true
                self.isStarting = false
                self.showFrameOverlay(for: displayID)
            } catch {
                self.isStarting = false
                // Räumt einen ggf. schon erzeugten virtuellen Bildschirm ab
                await self.teardown()
                self.showError(error, title: "Übertragung konnte nicht gestartet werden")
            }
        }
    }

    /// Pixelgröße des Ausschnitts = Auflösung des virtuellen Bildschirms.
    private func cropPixelSize(
        for displayID: CGDirectDisplayID, configuration: CropConfiguration
    ) -> CGSize? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else { return nil }
        let crop = CropCalculator.cropRect(
            displaySize: screen.frame.size, configuration: configuration)
        let scale = screen.backingScaleFactor
        return CGSize(width: crop.width * scale, height: crop.height * scale)
    }

    /// Zeigt den Rahmen um den aktuellen Ausschnitt bzw. verschiebt ihn.
    private func showFrameOverlay(for displayID: CGDirectDisplayID) {
        guard let configuration = activeConfiguration,
              let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else { return }
        let crop = CropCalculator.cropRect(
            displaySize: screen.frame.size, configuration: configuration)
        if let overlay = frameOverlayController {
            overlay.move(to: crop, on: screen)
        } else {
            frameOverlayController = CropFrameOverlayController(cropRect: crop, on: screen)
        }
    }

    @objc private func stopCapture() {
        Task { @MainActor in await self.teardown() }
    }

    /// Öffnet die Config-Datei im Standardprogramm für YAML-Dateien —
    /// identisch zum Doppelklick im Finder.
    @objc private func openConfigFile() {
        NSWorkspace.shared.open(configStore.fileURL)
    }

    // Liest die Config-Datei neu ein. Bei Fehlern bleibt die zuletzt
    // gültige Liste aktiv. Für eine laufende Übertragung gilt: aktive
    // Konfiguration (per Name) unverändert → weiterlaufen; Geometrie
    // geändert → Wechsel/Neustart; gelöscht → stoppen.
    @objc private func reloadConfig() {
        do {
            configurations = try configStore.load()
        } catch {
            showError(error, title: "Konfiguration konnte nicht geladen werden")
            return
        }

        guard isRunning, let active = activeConfiguration else { return }
        guard let updated = configurations.first(where: { $0.name == active.name })
        else {
            // Aktive Konfiguration wurde entfernt → Übertragung stoppen
            activeConfiguration = nil
            Task { @MainActor in await self.teardown() }
            return
        }
        guard updated != active else { return }
        if let displayID = activeDisplayID {
            switchConfiguration(to: updated, on: displayID)
        } else {
            activeConfiguration = updated
        }
    }

    @MainActor
    private func teardown(stopEngine: Bool = true) async {
        isRunning = false
        activeDisplayID = nil
        if stopEngine {
            await captureEngine.stop()
        }
        mirrorWindowController?.close()
        mirrorWindowController = nil
        frameOverlayController?.close()
        frameOverlayController = nil
        virtualDisplayController.destroy()
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Bildschirmaufnahme nicht erlaubt"
        alert.informativeText = """
            Screen Framer braucht die Berechtigung „Bildschirmaufnahme".
            Bitte in den Systemeinstellungen unter
            Datenschutz & Sicherheit → Bildschirmaufnahme aktivieren
            und die App danach neu starten.
            """
        alert.addButton(withTitle: "Systemeinstellungen öffnen")
        alert.addButton(withTitle: "Abbrechen")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showError(_ error: Error, title: String = "Übertragung beendet") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number.map { CGDirectDisplayID($0.uint32Value) }
    }
}

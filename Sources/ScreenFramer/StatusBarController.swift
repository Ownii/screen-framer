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
    private var position: CropPosition = .center
    private var isRunning = false
    private var isStarting = false

    private static let positionTitles: [(CropPosition, String)] = [
        (.left, "Links"), (.center, "Mitte"), (.right, "Rechts"),
    ]

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.center.inset.filled",
            accessibilityDescription: "Screen Framer")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
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

        for (value, title) in Self.positionTitles {
            let item = NSMenuItem(
                title: title, action: #selector(startTransmission(_:)), keyEquivalent: "")
            item.target =
                (clickedDisplayID != nil && !clickedIsVirtual && !isStarting) ? self : nil
            item.representedObject = value.rawValue
            item.state = (isRunning && value == position) ? .on : .off
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
        let quitItem = NSMenuItem(
            title: "Beenden", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // Klick auf Links/Mitte/Rechts: startet die Übertragung für den Monitor,
    // auf dem das Menü geöffnet wurde — bzw. schaltet nur die Position um,
    // wenn genau dieser Monitor bereits übertragen wird.
    @objc private func startTransmission(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let newPosition = CropPosition(rawValue: raw),
              let displayID = clickedDisplayID,
              displayID != virtualDisplayController.displayID,
              !isStarting else { return }

        if isRunning, displayID == activeDisplayID {
            guard newPosition != position else { return }
            let previousPosition = position
            position = newPosition
            Task { @MainActor in
                do {
                    try await self.captureEngine.updatePosition(newPosition)
                    // Zwischenzeitliches Teardown (z. B. Stream-Fehler): kein
                    // Overlay für eine beendete Übertragung wiederbeleben
                    guard self.isRunning, self.activeDisplayID == displayID else { return }
                    self.showFrameOverlay(for: displayID)
                } catch {
                    self.position = previousPosition
                    self.showError(error, title: "Positionswechsel fehlgeschlagen")
                }
            }
            return
        }

        position = newPosition
        startCapture(on: displayID)
    }

    private func startCapture(on displayID: CGDirectDisplayID) {
        guard !isStarting else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            showPermissionAlert()
            return
        }
        guard let pixelSize = cropPixelSize(for: displayID) else {
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
                    displayID: displayID, position: self.position)
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

    /// Pixelgröße des 16:9-Ausschnitts = Auflösung des virtuellen Bildschirms.
    /// (Unabhängig von der Position — Breite/Höhe sind für alle Anker gleich.)
    private func cropPixelSize(for displayID: CGDirectDisplayID) -> CGSize? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else { return nil }
        let crop = CropCalculator.cropRect(
            displaySize: screen.frame.size, position: position)
        let scale = screen.backingScaleFactor
        return CGSize(width: crop.width * scale, height: crop.height * scale)
    }

    /// Zeigt den Rahmen um den aktuellen Ausschnitt bzw. verschiebt ihn.
    private func showFrameOverlay(for displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else { return }
        let crop = CropCalculator.cropRect(
            displaySize: screen.frame.size, position: position)
        if let overlay = frameOverlayController {
            overlay.move(to: crop, on: screen)
        } else {
            frameOverlayController = CropFrameOverlayController(cropRect: crop, on: screen)
        }
    }

    @objc private func stopCapture() {
        Task { @MainActor in await self.teardown() }
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

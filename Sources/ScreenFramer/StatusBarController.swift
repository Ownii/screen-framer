import AppKit
import ScreenFramerCore

/// Menüleisten-Icon und Menü; hält den App-Zustand und verdrahtet
/// CaptureEngine und MirrorWindowController.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let captureEngine = CaptureEngine()
    private var mirrorWindowController: MirrorWindowController?

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

        if let clickedScreen {
            // Deaktivierter Info-Eintrag: zeigt, welcher Monitor übertragen würde
            let infoItem = NSMenuItem(
                title: "Monitor: \(clickedScreen.localizedName)", action: nil,
                keyEquivalent: "")
            menu.addItem(infoItem)
            menu.addItem(.separator())
        }

        for (value, title) in Self.positionTitles {
            let item = NSMenuItem(
                title: title, action: #selector(startTransmission(_:)), keyEquivalent: "")
            item.target = (clickedDisplayID != nil && !isStarting) ? self : nil
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
              !isStarting else { return }

        if isRunning, displayID == activeDisplayID {
            guard newPosition != position else { return }
            position = newPosition
            Task { @MainActor in
                do {
                    try await self.captureEngine.updatePosition(newPosition)
                } catch {
                    self.showError(error)
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

        isStarting = true
        Task { @MainActor in
            // Laufende Übertragung (z. B. auf dem anderen Monitor) zuerst beenden
            if self.isRunning {
                await self.teardown()
            }

            let windowController = MirrorWindowController()
            windowController.onClose = { [weak self] in
                guard let self, self.isRunning else { return }
                Task { @MainActor in await self.teardown(closeWindow: false) }
            }
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

            do {
                try await self.captureEngine.start(displayID: displayID, position: self.position)
                self.mirrorWindowController = windowController
                self.activeDisplayID = displayID
                self.isRunning = true
                self.isStarting = false
                windowController.showWindow(nil)
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                self.isStarting = false
                self.showError(error)
            }
        }
    }

    @objc private func stopCapture() {
        Task { @MainActor in await self.teardown() }
    }

    @MainActor
    private func teardown(stopEngine: Bool = true, closeWindow: Bool = true) async {
        isRunning = false
        activeDisplayID = nil
        if stopEngine {
            await captureEngine.stop()
        }
        if closeWindow, let controller = mirrorWindowController {
            controller.onClose = nil
            controller.close()
        }
        mirrorWindowController = nil
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

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Übertragung beendet"
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

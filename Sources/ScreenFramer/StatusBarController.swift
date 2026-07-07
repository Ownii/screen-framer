import AppKit
import ScreenFramerCore

/// Menüleisten-Icon und Menü; hält den App-Zustand und verdrahtet
/// CaptureEngine und MirrorWindowController.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let captureEngine = CaptureEngine()
    private var mirrorWindowController: MirrorWindowController?

    private var selectedDisplayID: CGDirectDisplayID?
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

    // Menü bei jedem Öffnen neu aufbauen (Monitore können sich ändern)
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let monitorItem = NSMenuItem(title: "Monitor", action: nil, keyEquivalent: "")
        let monitorMenu = NSMenu()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let item = NSMenuItem(
                title: screen.localizedName,
                action: #selector(selectMonitor(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: id)
            item.state = (id == selectedDisplayID) ? .on : .off
            monitorMenu.addItem(item)
        }
        monitorItem.submenu = monitorMenu
        menu.addItem(monitorItem)

        let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let positionMenu = NSMenu()
        for (value, title) in Self.positionTitles {
            let item = NSMenuItem(
                title: title, action: #selector(selectPosition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value.rawValue
            item.state = (value == position) ? .on : .off
            positionMenu.addItem(item)
        }
        positionItem.submenu = positionMenu
        menu.addItem(positionItem)

        menu.addItem(.separator())
        if isRunning {
            let stopItem = NSMenuItem(
                title: "Übertragung stoppen", action: #selector(stopCapture),
                keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            let startItem = NSMenuItem(
                title: "Übertragung starten", action: #selector(startCapture),
                keyEquivalent: "")
            // Ohne Monitorauswahl kein Start (target = nil → Item ausgegraut)
            startItem.target = (selectedDisplayID != nil && !isStarting) ? self : nil
            menu.addItem(startItem)
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Beenden", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    @objc private func selectMonitor(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        let newID = CGDirectDisplayID(number.uint32Value)
        guard newID != selectedDisplayID else { return }
        selectedDisplayID = newID
        if isRunning {
            // Monitorwechsel während laufender Übertragung: neu starten
            Task { @MainActor in
                await self.teardown()
                self.startCapture()
            }
        }
    }

    @objc private func selectPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let newPosition = CropPosition(rawValue: raw) else { return }
        position = newPosition
        if isRunning {
            Task { @MainActor in
                do {
                    try await self.captureEngine.updatePosition(newPosition)
                } catch {
                    self.showError(error)
                }
            }
        }
    }

    @objc private func startCapture() {
        guard let displayID = selectedDisplayID, !isRunning, !isStarting else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            showPermissionAlert()
            return
        }

        let windowController = MirrorWindowController()
        windowController.onClose = { [weak self] in
            guard let self, self.isRunning else { return }
            Task { @MainActor in await self.teardown(closeWindow: false) }
        }
        captureEngine.onFrame = { [weak windowController] buffer in
            windowController?.enqueue(buffer)
        }
        captureEngine.onStopped = { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                await self.teardown(stopEngine: false)
                if let error { self.showError(error) }
            }
        }

        isStarting = true
        Task { @MainActor in
            do {
                try await self.captureEngine.start(displayID: displayID, position: self.position)
                self.mirrorWindowController = windowController
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

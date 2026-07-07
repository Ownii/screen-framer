import AppKit
import ScreenFramerCore

/// Grüner, klick-durchlässiger Rahmen um den übertragenen Ausschnitt auf
/// dem Quellmonitor. Nur lokal sichtbar — `sharingType = .none` nimmt das
/// Fenster aus jedem Capture heraus, Teilnehmende sehen es nicht.
final class CropFrameOverlayController: NSWindowController {
    init(cropRect: CGRect, on screen: NSScreen) {
        let frame = CropCalculator.cocoaFrame(for: cropRect, in: screen.frame)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        // Für jedes Capture unsichtbar (unsere Übertragung, Teams, Screenshots).
        // Nicht aufs Vollbild-Fenster übertragen — das MUSS capturebar bleiben,
        // sonst sieht Teams auf dem virtuellen Bildschirm nur Schwarz.
        window.sharingType = .none
        // Über der Menüleiste, damit der Rahmen oben durchgängig sichtbar ist
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
        ]
        super.init(window: window)

        let view = NSView()
        view.wantsLayer = true
        view.layer?.borderColor = NSColor.systemGreen.cgColor
        view.layer?.borderWidth = 4
        window.contentView = view
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func move(to cropRect: CGRect, on screen: NSScreen) {
        let frame = CropCalculator.cocoaFrame(for: cropRect, in: screen.frame)
        window?.setFrame(frame, display: true)
    }
}

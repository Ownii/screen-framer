import AppKit
import AVFoundation

/// Randloses Vollbild-Fenster auf dem virtuellen Bildschirm; rendert
/// CMSampleBuffer via AVSampleBufferDisplayLayer (GPU-basiert, latenzarm).
final class MirrorWindowController: NSWindowController {
    private let displayLayer = AVSampleBufferDisplayLayer()

    init(screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        // Über der Menüleiste des virtuellen Bildschirms, sonst überdeckt
        // sie den oberen Rand des übertragenen Bildes
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        super.init(window: window)

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        let contentView = NSView()
        contentView.layer = displayLayer
        contentView.wantsLayer = true
        window.contentView = contentView
        window.setFrame(screen.frame, display: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
        }
        renderer.enqueue(sampleBuffer)
    }
}

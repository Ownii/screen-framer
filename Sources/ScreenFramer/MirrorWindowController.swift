import AppKit
import AVFoundation

/// Das Fenster, das in Teams geteilt wird: frei skalierbar,
/// Seitenverhältnis fest 16:9, rendert CMSampleBuffer via
/// AVSampleBufferDisplayLayer (GPU-basiert, latenzarm).
final class MirrorWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let displayLayer = AVSampleBufferDisplayLayer()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Screen Framer"
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        let contentView = NSView()
        contentView.layer = displayLayer
        contentView.wantsLayer = true
        window.contentView = contentView
        window.center()
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

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

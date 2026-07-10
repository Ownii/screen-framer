import AppKit
import AVFoundation
import ScreenCaptureKit
import ScreenFramerCore

enum CaptureError: LocalizedError {
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "Der gewählte Monitor wurde nicht gefunden. Ist er noch angeschlossen?"
        }
    }
}

/// Kapselt ScreenCaptureKit: baut den Stream mit 16:9-sourceRect auf,
/// liefert Frames über `onFrame` und meldet externe Stopps über `onStopped`.
final class CaptureEngine: NSObject {
    var onFrame: ((CMSampleBuffer) -> Void)?
    var onStopped: ((Error?) -> Void)?

    private var stream: SCStream?
    private var streamConfiguration: SCStreamConfiguration?
    private var displaySize: CGSize = .zero
    private var scaleFactor: CGFloat = 1
    private let sampleQueue = DispatchQueue(label: "de.martinfoerster.screen-framer.capture")

    func start(displayID: CGDirectDisplayID, configuration: CropConfiguration) async throws {
        // Bereits laufenden Stream sauber beenden, bevor ein neuer startet
        if stream != nil {
            await stop()
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        // Eigene App ausschließen → kein Spiegel-im-Spiegel-Effekt
        let ownBundleID = Bundle.main.bundleIdentifier
        let excludedApps = content.applications.filter {
            $0.bundleIdentifier == ownBundleID && ownBundleID != nil
        }
        let filter = SCContentFilter(
            display: display, excludingApplications: excludedApps, exceptingWindows: [])

        scaleFactor = NSScreen.screens.first { screen in
            let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == displayID
        }?.backingScaleFactor ?? 1

        displaySize = CGSize(width: display.width, height: display.height)
        let config = SCStreamConfiguration()
        applyCrop(configuration: configuration, to: config)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
        self.streamConfiguration = config
    }

    func update(configuration: CropConfiguration) async throws {
        guard let stream, let config = streamConfiguration else { return }
        applyCrop(configuration: configuration, to: config)
        try await stream.updateConfiguration(config)
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        self.streamConfiguration = nil
        try? await stream.stopCapture()
    }

    private func applyCrop(
        configuration: CropConfiguration, to config: SCStreamConfiguration
    ) {
        let crop = CropCalculator.cropRect(
            displaySize: displaySize, configuration: configuration)
        config.sourceRect = crop
        config.width = Int(crop.width * scaleFactor)
        config.height = Int(crop.height * scaleFactor)
    }
}

extension CaptureEngine: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }
        // Nur vollständige Frames weiterreichen
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let statusRaw = attachments.first?[.status] as? Int,
            statusRaw == SCFrameStatus.complete.rawValue
        else { return }
        onFrame?(sampleBuffer)
    }
}

extension CaptureEngine: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.streamConfiguration = nil
            self.onStopped?(error)
        }
    }
}

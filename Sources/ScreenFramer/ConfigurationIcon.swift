import AppKit
import ScreenFramerCore

/// Zeichnet Menü-Icons im Stil von Rectangle Pro: Monitor-Umriss mit
/// gefülltem Ausschnitt, berechnet aus der Grid-Konfiguration — dieselbe
/// Geometrie wie die echte Übertragung, nur im Miniaturformat.
enum ConfigurationIcon {
    private static let size = NSSize(width: 18, height: 12)

    static func image(for configuration: CropConfiguration) -> NSImage {
        // flipped: Ursprung oben links, wie CropCalculator.cropRect
        let image = NSImage(size: size, flipped: true) { rect in
            let outline = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1
            NSColor.black.withAlphaComponent(0.55).setStroke()
            outline.stroke()

            let crop = CropCalculator.cropRect(
                displaySize: rect.size, configuration: configuration)
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: crop.insetBy(dx: 1.25, dy: 1.25), xRadius: 1, yRadius: 1
            ).fill()
            return true
        }
        // Template: macOS färbt das Icon passend zu Menü-Theme und Highlight
        image.isTemplate = true
        return image
    }
}

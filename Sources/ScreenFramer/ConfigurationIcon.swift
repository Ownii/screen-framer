import AppKit
import ScreenFramerCore

/// Zeichnet Menü-Icons im Stil von Rectangle Pro: Monitor-Umriss mit
/// gefülltem Ausschnitt, berechnet aus der Grid-Konfiguration — dieselbe
/// Geometrie wie die echte Übertragung, nur im Miniaturformat.
enum ConfigurationIcon {
    private static let height: CGFloat = 12

    /// `displaySize` bestimmt das Seitenverhältnis des Icons, damit es dem
    /// Monitor entspricht, für den das Menü geöffnet wurde (32:9 → breit).
    static func image(
        for configuration: CropConfiguration, displaySize: CGSize
    ) -> NSImage {
        let aspect = displaySize.height > 0 ? displaySize.width / displaySize.height : 16.0 / 9.0
        // Breite begrenzen, damit extreme Monitore das Menü nicht sprengen
        let width = min(max((height * aspect).rounded(), 10), 42)
        let size = NSSize(width: width, height: height)

        // flipped: Ursprung oben links, wie CropCalculator.cropRect
        let image = NSImage(size: size, flipped: true) { rect in
            let outline = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1
            NSColor.black.withAlphaComponent(0.55).setStroke()
            outline.stroke()

            // Ausschnitt im Innenbereich des Rahmens berechnen — ein fester
            // Inset auf der vollen Icon-Fläche würde die Proportionen kleiner
            // Ausschnitte verfälschen (ein Viertel sähe nicht wie eins aus)
            let screenArea = rect.insetBy(dx: 2, dy: 2)
            var crop = CropCalculator.cropRect(
                displaySize: screenArea.size, configuration: configuration)
            crop.origin.x += screenArea.origin.x
            crop.origin.y += screenArea.origin.y
            // Radius nie über die halbe Kantenlänge, sonst kollabiert der Pfad
            let radius = min(1, min(crop.width, crop.height) / 2)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: crop, xRadius: radius, yRadius: radius).fill()
            return true
        }
        // Template: macOS färbt das Icon passend zu Menü-Theme und Highlight
        image.isTemplate = true
        return image
    }
}

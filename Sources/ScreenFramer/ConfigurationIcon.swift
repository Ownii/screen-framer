import AppKit
import ScreenFramerCore

/// Zeichnet Ausschnitt-Icons im Stil von Rectangle Pro: Monitor-Umriss mit
/// gefülltem Ausschnitt, berechnet aus der Grid-Konfiguration — dieselbe
/// Geometrie wie die echte Übertragung, nur im Miniaturformat.
enum ConfigurationIcon {
    private static let height: CGFloat = 12

    /// Icon-Größe im Seitenverhältnis des Monitors, für den das Menü
    /// geöffnet wurde (32:9 → breit).
    static func size(forDisplaySize displaySize: CGSize) -> NSSize {
        let aspect = displaySize.height > 0 ? displaySize.width / displaySize.height : 16.0 / 9.0
        // Breite begrenzen, damit extreme Monitore das Menü nicht sprengen
        let width = min(max((height * aspect).rounded(), 10), 42)
        return NSSize(width: width, height: height)
    }

    /// Zeichnet das Icon in `rect` des aktuellen (nach oben-links
    /// orientierten) Kontexts. `color` färbt Umriss und Füllung, damit das
    /// Icon der Textfarbe folgt (z. B. weiß im markierten Menüeintrag).
    static func draw(_ configuration: CropConfiguration, in rect: NSRect, color: NSColor) {
        let outline = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
        outline.lineWidth = 1
        color.withAlphaComponent(0.55).setStroke()
        outline.stroke()

        // Ausschnitt im Innenbereich des Rahmens berechnen — ein fester Inset
        // auf der vollen Icon-Fläche würde die Proportionen kleiner Ausschnitte
        // verfälschen (ein Viertel sähe nicht wie eins aus)
        let screenArea = rect.insetBy(dx: 2, dy: 2)
        var crop = CropCalculator.cropRect(
            displaySize: screenArea.size, configuration: configuration)
        crop.origin.x += screenArea.origin.x
        crop.origin.y += screenArea.origin.y
        // Radius nie über die halbe Kantenlänge, sonst kollabiert der Pfad
        let radius = min(1, min(crop.width, crop.height) / 2)
        color.setFill()
        NSBezierPath(roundedRect: crop, xRadius: radius, yRadius: radius).fill()
    }
}

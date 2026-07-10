import AppKit
import ScreenFramerCore

/// Zeichnet Menü-Icons im Stil von Rectangle Pro: Monitor-Umriss mit
/// gefülltem Ausschnitt, berechnet aus der Grid-Konfiguration — dieselbe
/// Geometrie wie die echte Übertragung, nur im Miniaturformat.
enum ConfigurationIcon {
    private static let height: CGFloat = 12

    /// Menü-Titel mit rechtsbündigem Icon: Name, Tabstopp, Icon als
    /// Text-Attachment. `titleColumnWidth` ist die Breite des längsten
    /// Namens, damit die Icons aller Einträge in einer Spalte fluchten.
    static func attributedTitle(
        for configuration: CropConfiguration, displaySize: CGSize,
        titleColumnWidth: CGFloat
    ) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let icon = image(for: configuration, displaySize: displaySize)

        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [
            NSTextTab(textAlignment: .left, location: titleColumnWidth + 14)
        ]
        paragraph.lineBreakMode = .byClipping

        let title = NSMutableAttributedString(
            string: configuration.name + "\t",
            attributes: [.font: font, .paragraphStyle: paragraph])
        let attachment = NSTextAttachment()
        attachment.image = icon
        // Vertikal an der Versalhöhe zentrieren, sonst hängt das Icon zu tief
        attachment.bounds = NSRect(
            x: 0, y: (font.capHeight - icon.size.height) / 2,
            width: icon.size.width, height: icon.size.height)
        title.append(NSAttributedString(attachment: attachment))
        return title
    }

    /// `displaySize` bestimmt das Seitenverhältnis des Icons, damit es dem
    /// Monitor entspricht, für den das Menü geöffnet wurde (32:9 → breit).
    static func image(
        for configuration: CropConfiguration, displaySize: CGSize
    ) -> NSImage {
        let aspect = displaySize.height > 0 ? displaySize.width / displaySize.height : 16.0 / 9.0
        // Breite begrenzen, damit extreme Monitore das Menü nicht sprengen
        let width = min(max((height * aspect).rounded(), 10), 42)
        let size = NSSize(width: width, height: height)

        // flipped: Ursprung oben links, wie CropCalculator.cropRect.
        // labelColor statt Template: Als Text-Attachment wird das Icon nicht
        // getintet; labelColor löst beim Zeichnen je nach Hell/Dunkel auf.
        let image = NSImage(size: size, flipped: true) { rect in
            let outline = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1
            NSColor.labelColor.withAlphaComponent(0.55).setStroke()
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
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: crop, xRadius: radius, yRadius: radius).fill()
            return true
        }
        return image
    }
}

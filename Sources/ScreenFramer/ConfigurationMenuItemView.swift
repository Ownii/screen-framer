import AppKit
import ScreenFramerCore

/// Eigenes View für einen Konfigurations-Menüeintrag. Nötig, weil ein
/// normaler `NSMenuItem` das Icon nicht rechtsbündig anzeigen kann: Der
/// Titel-Tabstopp reicht nie über den längsten Texteintrag hinaus. Dieses
/// View heftet das Icon fest an die rechte Kante und zeichnet Markierung,
/// Häkchen, Name und Icon selbst.
final class ConfigurationMenuItemView: NSView {
    private let configuration: CropConfiguration
    private let displaySize: CGSize
    private let isActive: Bool
    private let isEnabled: Bool
    private let onSelect: () -> Void

    private let leadingInset: CGFloat = 21
    private let trailingInset: CGFloat = 13
    private let iconGap: CGFloat = 24

    init(
        configuration: CropConfiguration, displaySize: CGSize,
        isActive: Bool, isEnabled: Bool, width: CGFloat, onSelect: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.displaySize = displaySize
        self.isActive = isActive
        self.isEnabled = isEnabled
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // oben-links wie CropCalculator, damit Zeilen-Grids richtig herum sind
    override var isFlipped: Bool { true }

    /// Mindestbreite, damit Name, Abstand und Icon hineinpassen.
    func fittingWidth() -> CGFloat {
        let nameWidth = (configuration.name as NSString)
            .size(withAttributes: [.font: Self.font]).width
        let iconWidth = ConfigurationIcon.size(forDisplaySize: displaySize).width
        return leadingInset + ceil(nameWidth) + iconGap + iconWidth + trailingInset
    }

    private static var font: NSFont { NSFont.menuFont(ofSize: 0) }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = isEnabled && (enclosingMenuItem?.isHighlighted ?? false)
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 5, yRadius: 5
            ).fill()
        }

        let color: NSColor =
            !isEnabled
            ? .disabledControlTextColor
            : (highlighted ? .alternateSelectedControlTextColor : .labelColor)

        if isActive {
            let mark = NSAttributedString(
                string: "✓", attributes: [.font: Self.font, .foregroundColor: color])
            let size = mark.size()
            mark.draw(at: NSPoint(
                x: (leadingInset - size.width) / 2,
                y: (bounds.height - size.height) / 2))
        }

        let name = NSAttributedString(
            string: configuration.name,
            attributes: [.font: Self.font, .foregroundColor: color])
        let nameSize = name.size()
        name.draw(at: NSPoint(x: leadingInset, y: (bounds.height - nameSize.height) / 2))

        let iconSize = ConfigurationIcon.size(forDisplaySize: displaySize)
        let iconRect = NSRect(
            x: bounds.width - trailingInset - iconSize.width,
            y: (bounds.height - iconSize.height) / 2,
            width: iconSize.width, height: iconSize.height)
        ConfigurationIcon.draw(configuration, in: iconRect, color: color)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        onSelect()
    }

    // Markierung folgt dem Mauszeiger: bei Ein-/Austritt neu zeichnen
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.activeAlways, .mouseEnteredAndExited],
            owner: self))
    }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }
}

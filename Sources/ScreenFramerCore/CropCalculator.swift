import CoreGraphics

public enum CropPosition: String, CaseIterable, Sendable {
    case left, center, right
}

public enum CropCalculator {
    /// 16:9-Ausschnitt (in Punkten) für ein Display der gegebenen Größe.
    /// Höhe = volle Displayhöhe; ist das Display schmaler als 16:9,
    /// wird die volle Breite verwendet.
    public static func cropRect(displaySize: CGSize, position: CropPosition) -> CGRect {
        let targetWidth = min(displaySize.width, (displaySize.height * 16.0 / 9.0).rounded())
        let x: CGFloat
        switch position {
        case .left:
            x = 0
        case .center:
            x = ((displaySize.width - targetWidth) / 2).rounded(.down)
        case .right:
            x = displaySize.width - targetWidth
        }
        return CGRect(x: x, y: 0, width: targetWidth, height: displaySize.height)
    }

    /// Ausschnitt (in Punkten, Ursprung oben links) für eine
    /// Grid-Konfiguration. Zellgrenzen sind gerundete Display-Bruchteile,
    /// dadurch stoßen benachbarte Ausschnitte lückenlos aneinander.
    public static func cropRect(
        displaySize: CGSize, configuration: CropConfiguration
    ) -> CGRect {
        func boundary(_ index: Int, of count: Int, in size: CGFloat) -> CGFloat {
            (size * CGFloat(index) / CGFloat(count)).rounded()
        }
        let left = boundary(
            configuration.column, of: configuration.gridColumns,
            in: displaySize.width)
        let right = boundary(
            configuration.column + configuration.columnSpan,
            of: configuration.gridColumns, in: displaySize.width)
        let top = boundary(
            configuration.row, of: configuration.gridRows,
            in: displaySize.height)
        let bottom = boundary(
            configuration.row + configuration.rowSpan,
            of: configuration.gridRows, in: displaySize.height)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Rechnet ein display-lokales Rechteck (Ursprung oben links, wie
    /// `cropRect`) in ein globales Cocoa-Frame (Ursprung unten links) um.
    /// `screenFrame` ist das globale Frame des Monitors (`NSScreen.frame`).
    public static func cocoaFrame(for cropRect: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.origin.x + cropRect.origin.x,
            y: screenFrame.origin.y + screenFrame.height - cropRect.maxY,
            width: cropRect.width,
            height: cropRect.height)
    }
}

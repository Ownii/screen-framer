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
}

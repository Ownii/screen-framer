import AppKit
import CGVirtualDisplayShim

enum VirtualDisplayError: LocalizedError {
    case creationFailed
    case screenNotFound

    var errorDescription: String? {
        switch self {
        case .creationFailed:
            return """
                Der virtuelle Bildschirm konnte nicht erstellt werden. \
                Möglicherweise hat ein macOS-Update die verwendete \
                Schnittstelle geändert.
                """
        case .screenNotFound:
            return "Der virtuelle Bildschirm wurde von macOS nicht registriert."
        }
    }
}

/// Erzeugt und zerstört den virtuellen Bildschirm (Lebensdauer: eine
/// Übertragung) und wartet nach der Erzeugung darauf, dass macOS den
/// zugehörigen NSScreen registriert.
final class VirtualDisplayController {
    private var virtualDisplay: SFVirtualDisplay?

    var displayID: CGDirectDisplayID? {
        virtualDisplay?.displayID
    }

    @MainActor
    func create(name: String, pixelSize: CGSize) async throws -> NSScreen {
        guard let display = SFVirtualDisplay(
            name: name,
            pixelWidth: UInt(pixelSize.width),
            pixelHeight: UInt(pixelSize.height))
        else {
            throw VirtualDisplayError.creationFailed
        }
        virtualDisplay = display

        // Auf die NSScreen-Registrierung warten (Polling, max. 2 s)
        let targetID = display.displayID
        for _ in 0..<40 {
            if let screen = NSScreen.screens.first(where: { $0.displayID == targetID }) {
                return screen
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        destroy()
        throw VirtualDisplayError.screenNotFound
    }

    /// Die Freigabe der SFVirtualDisplay-Instanz entfernt den Bildschirm.
    func destroy() {
        virtualDisplay = nil
    }
}

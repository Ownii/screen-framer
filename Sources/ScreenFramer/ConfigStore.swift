import Foundation
import ScreenFramerCore

/// Lädt die YAML-Konfigurationsdatei und legt sie beim ersten Start mit
/// den drei Seed-Konfigurationen an.
final class ConfigStore {
    let fileURL: URL

    init() {
        fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/screen-framer/config.yaml")
    }

    /// Legt Ordner und Datei mit den Seeds an, falls sie fehlen, und lädt.
    func loadCreatingIfMissing() throws -> [CropConfiguration] {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try Self.seedContent.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return try load()
    }

    func load() throws -> [CropConfiguration] {
        try ConfigurationParser.parse(
            yaml: String(contentsOf: fileURL, encoding: .utf8))
    }

    private static let seedContent = """
        # Screen Framer – Ausschnitt-Konfigurationen
        #
        # Jede Konfiguration teilt den Monitor in ein Grid und beschreibt den
        # übertragenen Ausschnitt über Position und Span (alles 0-basiert):
        #
        #   grid:     columns/rows – Spalten/Zeilen des Rasters (Default je 1)
        #   position: column/row   – Zelle oben links des Ausschnitts (Default 0/0)
        #   span:     columns/rows – Ausdehnung in Zellen (Default: bis zum Grid-Ende)
        configurations:
          - name: Links
            grid:
              columns: 2
            position:
              column: 0
            span:
              columns: 1

          - name: Mitte
            grid:
              columns: 4
            position:
              column: 1
            span:
              columns: 2

          - name: Rechts
            grid:
              columns: 2
            position:
              column: 1
        """
}

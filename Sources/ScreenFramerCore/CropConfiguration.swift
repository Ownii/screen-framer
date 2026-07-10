import Foundation
import Yams

/// Benutzerdefinierte Ausschnitt-Konfiguration: teilt den Monitor in ein
/// Grid und beschreibt den Ausschnitt über Position (Zelle oben links,
/// 0-basiert) und Span (Ausdehnung in Zellen).
public struct CropConfiguration: Equatable, Sendable {
    public var name: String
    public var gridColumns: Int
    public var gridRows: Int
    public var column: Int
    public var row: Int
    public var columnSpan: Int
    public var rowSpan: Int

    /// `columnSpan`/`rowSpan` = nil → Span reicht bis zum Grid-Ende.
    public init(
        name: String, gridColumns: Int = 1, gridRows: Int = 1,
        column: Int = 0, row: Int = 0,
        columnSpan: Int? = nil, rowSpan: Int? = nil
    ) {
        self.name = name
        self.gridColumns = gridColumns
        self.gridRows = gridRows
        self.column = column
        self.row = row
        self.columnSpan = columnSpan ?? gridColumns - column
        self.rowSpan = rowSpan ?? gridRows - row
    }
}

extension CropConfiguration: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, grid, position, span
    }
    private struct Axes: Decodable {
        var columns: Int?
        var rows: Int?
    }
    private struct Cell: Decodable {
        var column: Int?
        var row: Int?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let grid = try container.decodeIfPresent(Axes.self, forKey: .grid)
        let position = try container.decodeIfPresent(Cell.self, forKey: .position)
        let span = try container.decodeIfPresent(Axes.self, forKey: .span)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            gridColumns: grid?.columns ?? 1,
            gridRows: grid?.rows ?? 1,
            column: position?.column ?? 0,
            row: position?.row ?? 0,
            columnSpan: span?.columns,
            rowSpan: span?.rows)
    }
}

public enum ConfigurationError: LocalizedError, Equatable {
    case invalidYAML(String)

    public var errorDescription: String? {
        switch self {
        case .invalidYAML(let detail):
            return "Die Konfigurationsdatei ist kein gültiges YAML: \(detail)"
        }
    }
}

public enum ConfigurationParser {
    private struct ConfigFile: Decodable {
        var configurations: [CropConfiguration]
    }

    /// Parst den kompletten Dateiinhalt (Liste unter `configurations:`).
    public static func parse(yaml: String) throws -> [CropConfiguration] {
        let file: ConfigFile
        do {
            file = try YAMLDecoder().decode(ConfigFile.self, from: yaml)
        } catch {
            throw ConfigurationError.invalidYAML(String(describing: error))
        }
        return file.configurations
    }
}

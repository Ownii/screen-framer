import XCTest
@testable import ScreenFramerCore

final class CropConfigurationTests: XCTestCase {

    // Vollständiger Eintrag: alle Felder explizit
    func testParsesFullEntry() throws {
        let yaml = """
            configurations:
              - name: Mitte
                grid:
                  columns: 4
                  rows: 2
                position:
                  column: 1
                  row: 1
                span:
                  columns: 2
                  rows: 1
            """
        let configs = try ConfigurationParser.parse(yaml: yaml)
        XCTAssertEqual(configs, [
            CropConfiguration(
                name: "Mitte", gridColumns: 4, gridRows: 2,
                column: 1, row: 1, columnSpan: 2, rowSpan: 1)
        ])
    }

    // Nur ein Name: Grid 1×1, Position 0/0, Span = ganzes Grid
    func testMinimalEntryUsesAllDefaults() throws {
        let configs = try ConfigurationParser.parse(yaml: """
            configurations:
              - name: Alles
            """)
        XCTAssertEqual(configs, [
            CropConfiguration(
                name: "Alles", gridColumns: 1, gridRows: 1,
                column: 0, row: 0, columnSpan: 1, rowSpan: 1)
        ])
    }

    // Fehlender Span reicht von der Position bis zum Grid-Ende
    func testSpanDefaultsToGridEnd() throws {
        let configs = try ConfigurationParser.parse(yaml: """
            configurations:
              - name: Rechts
                grid:
                  columns: 3
                position:
                  column: 1
            """)
        XCTAssertEqual(configs.first?.columnSpan, 2)
        XCTAssertEqual(configs.first?.rowSpan, 1)
    }

    // rows-Defaults sind unabhängig von columns
    func testRowDefaultsIndependentOfColumns() throws {
        let configs = try ConfigurationParser.parse(yaml: """
            configurations:
              - name: Unten
                grid:
                  columns: 2
                  rows: 3
                position:
                  row: 1
            """)
        XCTAssertEqual(configs, [
            CropConfiguration(
                name: "Unten", gridColumns: 2, gridRows: 3,
                column: 0, row: 1, columnSpan: 2, rowSpan: 2)
        ])
    }

    func testEmptyListParses() throws {
        let configs = try ConfigurationParser.parse(yaml: "configurations: []")
        XCTAssertEqual(configs, [])
    }

    func testInvalidYAMLThrows() {
        XCTAssertThrowsError(try ConfigurationParser.parse(yaml: "configurations: [")) { error in
            guard case ConfigurationError.invalidYAML = error else {
                return XCTFail("Erwartet invalidYAML, war \(error)")
            }
        }
    }

    // MARK: - Validierung

    private func assertParseThrows(
        _ yaml: String, _ expected: ConfigurationError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try ConfigurationParser.parse(yaml: yaml), file: file, line: line
        ) { error in
            XCTAssertEqual(
                error as? ConfigurationError, expected, file: file, line: line)
        }
    }

    func testEmptyNameThrows() {
        assertParseThrows("""
            configurations:
              - name: "  "
            """, .emptyName)
    }

    func testDuplicateNameThrows() {
        assertParseThrows("""
            configurations:
              - name: Links
              - name: Links
            """, .duplicateName("Links"))
    }

    func testZeroGridThrows() {
        assertParseThrows("""
            configurations:
              - name: Kaputt
                grid:
                  columns: 0
            """, .invalidGrid(name: "Kaputt"))
    }

    func testPositionOutsideGridThrows() {
        assertParseThrows("""
            configurations:
              - name: Daneben
                grid:
                  columns: 2
                position:
                  column: 2
            """, .positionOutsideGrid(name: "Daneben"))
    }

    func testZeroSpanThrows() {
        assertParseThrows("""
            configurations:
              - name: Leer
                grid:
                  columns: 2
                span:
                  columns: 0
            """, .invalidSpan(name: "Leer"))
    }

    func testSpanBeyondGridThrows() {
        assertParseThrows("""
            configurations:
              - name: Zuweit
                grid:
                  columns: 3
                position:
                  column: 1
                span:
                  columns: 3
            """, .spanExceedsGrid(name: "Zuweit"))
    }

    // MARK: - displays (Monitor-Bindung)

    func testParsesDisplaysList() throws {
        let configs = try ConfigurationParser.parse(yaml: """
            configurations:
              - name: Nur Ultrawide
                displays:
                  - "UUID-A"
                  - "UUID-B"
            """)
        XCTAssertEqual(configs.first?.displays, ["UUID-A", "UUID-B"])
    }

    func testMissingDisplaysIsNil() throws {
        let configs = try ConfigurationParser.parse(yaml: """
            configurations:
              - name: Überall
            """)
        XCTAssertNil(configs.first?.displays)
    }

    func testEmptyDisplaysListIsNil() throws {
        let configs = try ConfigurationParser.parse(yaml: """
            configurations:
              - name: Überall
                displays: []
            """)
        XCTAssertNil(configs.first?.displays)
    }

    func testWhitespaceDisplaysEntriesAreDropped() throws {
        let configs = try ConfigurationParser.parse(yaml: """
            configurations:
              - name: Gemischt
                displays:
                  - "  "
                  - " UUID-A "
            """)
        XCTAssertEqual(configs.first?.displays, ["UUID-A"])
    }

    func testMatchesWithoutDisplaysAlwaysTrue() {
        let config = CropConfiguration(name: "Überall")
        XCTAssertTrue(config.matches(displayUUID: "UUID-A"))
        XCTAssertTrue(config.matches(displayUUID: nil))
    }

    func testMatchesOnlyListedDisplays() {
        let config = CropConfiguration(name: "Gebunden", displays: ["UUID-A"])
        XCTAssertTrue(config.matches(displayUUID: "UUID-A"))
        XCTAssertFalse(config.matches(displayUUID: "UUID-B"))
        XCTAssertFalse(config.matches(displayUUID: nil))
    }
}

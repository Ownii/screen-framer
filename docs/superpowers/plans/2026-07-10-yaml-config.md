# YAML-Konfigurationen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die drei fest einprogrammierten 16:9-Ausschnitte durch benutzerdefinierbare Grid-Konfigurationen aus `~/.config/screen-framer/config.yaml` ersetzen, plus Menüeinträge zum Öffnen und Neuladen der Datei.

**Architecture:** `ScreenFramerCore` bekommt das Config-Modell (`CropConfiguration`) mit Yams-basiertem Parsing, Default-Logik, Validierung und Grid-Rechteck-Berechnung — alles unit-getestet. Das App-Target bekommt einen dünnen `ConfigStore` (Pfad, Seed-Anlage, Laden); `StatusBarController` und `CaptureEngine` werden von `CropPosition` auf `CropConfiguration` umgestellt.

**Tech Stack:** Swift 5.10, SPM, macOS 14+, Yams (neue Dependency, nur in `ScreenFramerCore`), XCTest.

**Spec:** `docs/superpowers/specs/2026-07-10-yaml-config-design.md`

## Global Constraints

- UI-Texte und Code-Kommentare auf Deutsch (bestehender Stil).
- Indizierung in der Config-Datei ist **0-basiert**.
- Default-Regeln: `grid.columns`/`grid.rows` fehlt → `1`; `position.column`/`position.row` fehlt → `0`; `span.columns`/`span.rows` fehlt → bis zum Grid-Ende (`grid - position`).
- Einzige neue Dependency: `Yams` (https://github.com/jpsim/Yams.git, `from: "5.1.0"`). Keine weiteren.
- Config-Pfad: `~/.config/screen-framer/config.yaml`.
- Tests laufen mit `swift test` (alias `make test`); die App baut/startet mit `make restart`.
- `CropPosition` und das 16:9-Verhalten entfallen ersatzlos (Task 5).

---

### Task 1: Yams-Dependency + `CropConfiguration` mit Default-Parsing

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ScreenFramerCore/CropConfiguration.swift`
- Test: `Tests/ScreenFramerCoreTests/CropConfigurationTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `public struct CropConfiguration: Equatable, Sendable` mit Properties `name: String`, `gridColumns: Int`, `gridRows: Int`, `column: Int`, `row: Int`, `columnSpan: Int`, `rowSpan: Int` und memberwise Init `init(name:gridColumns:gridRows:column:row:columnSpan:rowSpan:)` (Defaults: 1, 1, 0, 0, nil, nil — `nil`-Span → bis Grid-Ende)
  - `public enum ConfigurationParser` mit `static func parse(yaml: String) throws -> [CropConfiguration]`
  - `public enum ConfigurationError: LocalizedError, Equatable` (in diesem Task nur Case `invalidYAML(String)`; Task 2 ergänzt die übrigen)

- [ ] **Step 1: Yams als Dependency eintragen**

`Package.swift` komplett ersetzen durch:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScreenFramer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .target(name: "ScreenFramerCore", dependencies: ["Yams"]),
        .target(name: "CGVirtualDisplayShim"),
        .executableTarget(
            name: "ScreenFramer",
            dependencies: ["ScreenFramerCore", "CGVirtualDisplayShim"]
        ),
        .testTarget(
            name: "ScreenFramerCoreTests",
            dependencies: ["ScreenFramerCore"]
        ),
    ]
)
```

Run: `swift build`
Expected: Yams wird aufgelöst und gebaut, Build erfolgreich.

- [ ] **Step 2: Fehlschlagende Tests schreiben**

`Tests/ScreenFramerCoreTests/CropConfigurationTests.swift` anlegen:

```swift
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
}
```

- [ ] **Step 3: Tests laufen lassen — sie müssen fehlschlagen**

Run: `swift test --filter CropConfigurationTests`
Expected: Compile-Fehler „cannot find 'ConfigurationParser' in scope" (Typ existiert noch nicht).

- [ ] **Step 4: Modell und Parser implementieren**

`Sources/ScreenFramerCore/CropConfiguration.swift` anlegen:

```swift
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
```

- [ ] **Step 5: Tests laufen lassen — sie müssen grün sein**

Run: `swift test --filter CropConfigurationTests`
Expected: 6 Tests, alle PASS. Danach `swift test` (alles), Expected: alle PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Package.resolved Sources/ScreenFramerCore/CropConfiguration.swift Tests/ScreenFramerCoreTests/CropConfigurationTests.swift
git commit -m "feat: parse YAML crop configurations with defaults"
```

---

### Task 2: Validierung der Konfigurationen

**Files:**
- Modify: `Sources/ScreenFramerCore/CropConfiguration.swift`
- Test: `Tests/ScreenFramerCoreTests/CropConfigurationTests.swift`

**Interfaces:**
- Consumes: `CropConfiguration`, `ConfigurationParser.parse(yaml:)`, `ConfigurationError` aus Task 1
- Produces:
  - `ConfigurationError` bekommt die Cases `emptyName`, `duplicateName(String)`, `invalidGrid(name: String)`, `positionOutsideGrid(name: String)`, `invalidSpan(name: String)`, `spanExceedsGrid(name: String)`
  - `parse(yaml:)` validiert jetzt: wirft bei ungültigen Einträgen statt sie zurückzugeben

- [ ] **Step 1: Fehlschlagende Tests ergänzen**

In `Tests/ScreenFramerCoreTests/CropConfigurationTests.swift` anhängen:

```swift
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
```

- [ ] **Step 2: Tests laufen lassen — sie müssen fehlschlagen**

Run: `swift test --filter CropConfigurationTests`
Expected: Compile-Fehler „type 'ConfigurationError' has no member 'emptyName'".

- [ ] **Step 3: Validierung implementieren**

In `Sources/ScreenFramerCore/CropConfiguration.swift` den `ConfigurationError` ersetzen und die Validierung ergänzen:

```swift
public enum ConfigurationError: LocalizedError, Equatable {
    case invalidYAML(String)
    case emptyName
    case duplicateName(String)
    case invalidGrid(name: String)
    case positionOutsideGrid(name: String)
    case invalidSpan(name: String)
    case spanExceedsGrid(name: String)

    public var errorDescription: String? {
        switch self {
        case .invalidYAML(let detail):
            return "Die Konfigurationsdatei ist kein gültiges YAML: \(detail)"
        case .emptyName:
            return "Eine Konfiguration hat keinen Namen."
        case .duplicateName(let name):
            return "Der Konfigurationsname „\(name)" wird mehrfach verwendet."
        case .invalidGrid(let name):
            return "„\(name)": grid.columns und grid.rows müssen mindestens 1 sein."
        case .positionOutsideGrid(let name):
            return "„\(name)": Die Position liegt außerhalb des Grids (0-basiert)."
        case .invalidSpan(let name):
            return "„\(name)": span.columns und span.rows müssen mindestens 1 sein."
        case .spanExceedsGrid(let name):
            return "„\(name)": Position + Span ragt über das Grid hinaus."
        }
    }
}
```

In `CropConfiguration` (struct-Body) eine Validierungsfunktion ergänzen:

```swift
    /// Wirft einen `ConfigurationError`, wenn der Eintrag in sich
    /// widersprüchlich ist (Position/Span außerhalb des Grids etc.).
    public func validate() throws {
        guard gridColumns >= 1, gridRows >= 1 else {
            throw ConfigurationError.invalidGrid(name: name)
        }
        guard (0..<gridColumns).contains(column), (0..<gridRows).contains(row) else {
            throw ConfigurationError.positionOutsideGrid(name: name)
        }
        guard columnSpan >= 1, rowSpan >= 1 else {
            throw ConfigurationError.invalidSpan(name: name)
        }
        guard column + columnSpan <= gridColumns, row + rowSpan <= gridRows else {
            throw ConfigurationError.spanExceedsGrid(name: name)
        }
    }
```

In `ConfigurationParser.parse(yaml:)` nach dem Decoden validieren (vor dem `return`):

```swift
        var seenNames = Set<String>()
        for configuration in file.configurations {
            guard !configuration.name.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ConfigurationError.emptyName
            }
            guard seenNames.insert(configuration.name).inserted else {
                throw ConfigurationError.duplicateName(configuration.name)
            }
            try configuration.validate()
        }
        return file.configurations
```

- [ ] **Step 4: Tests laufen lassen — sie müssen grün sein**

Run: `swift test --filter CropConfigurationTests`
Expected: 12 Tests, alle PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenFramerCore/CropConfiguration.swift Tests/ScreenFramerCoreTests/CropConfigurationTests.swift
git commit -m "feat: validate crop configurations"
```

---

### Task 3: Grid-Rechteck-Berechnung im `CropCalculator`

**Files:**
- Modify: `Sources/ScreenFramerCore/CropCalculator.swift`
- Test: `Tests/ScreenFramerCoreTests/CropCalculatorTests.swift`

**Interfaces:**
- Consumes: `CropConfiguration` aus Task 1
- Produces: `CropCalculator.cropRect(displaySize: CGSize, configuration: CropConfiguration) -> CGRect` — display-lokal, Ursprung oben links (wie die bestehende `cocoaFrame(for:in:)` es erwartet). Die alte `cropRect(displaySize:position:)` bleibt in diesem Task bestehen (wird erst in Task 5 entfernt).

- [ ] **Step 1: Fehlschlagende Tests schreiben**

In `Tests/ScreenFramerCoreTests/CropCalculatorTests.swift` anhängen:

```swift
    // MARK: - cropRect(displaySize:configuration:)

    // Seeds auf dem 32:9-Monitor (5120×1440): Links/Mitte/Rechts als Grid
    func testGridSeedLeftHalf() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 5120, height: 1440),
            configuration: CropConfiguration(
                name: "Links", gridColumns: 2, column: 0, columnSpan: 1))
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 2560, height: 1440))
    }

    func testGridSeedMiddleHalf() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 5120, height: 1440),
            configuration: CropConfiguration(
                name: "Mitte", gridColumns: 4, column: 1, columnSpan: 2))
        XCTAssertEqual(rect, CGRect(x: 1280, y: 0, width: 2560, height: 1440))
    }

    func testGridSeedRightHalf() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 5120, height: 1440),
            configuration: CropConfiguration(
                name: "Rechts", gridColumns: 2, column: 1))
        XCTAssertEqual(rect, CGRect(x: 2560, y: 0, width: 2560, height: 1440))
    }

    // Defaults (Grid 1×1) → ganzer Monitor
    func testGridDefaultsGiveFullDisplay() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 2560, height: 1080),
            configuration: CropConfiguration(name: "Alles"))
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 2560, height: 1080))
    }

    // Zeilen-Grid: mittleres Drittel der Höhe
    func testGridRowsSelectHorizontalBand() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 1000, height: 900),
            configuration: CropConfiguration(
                name: "Band", gridRows: 3, row: 1, rowSpan: 1))
        XCTAssertEqual(rect, CGRect(x: 0, y: 300, width: 1000, height: 300))
    }

    // Ungerade Breite: gerundete Zellgrenzen, benachbarte Zellen lückenlos
    func testGridBoundariesAreRoundedAndGapless() {
        let size = CGSize(width: 1001, height: 500)
        let cells = (0..<3).map { column in
            CropCalculator.cropRect(
                displaySize: size,
                configuration: CropConfiguration(
                    name: "Zelle", gridColumns: 3, column: column, columnSpan: 1))
        }
        XCTAssertEqual(cells[0], CGRect(x: 0, y: 0, width: 334, height: 500))
        XCTAssertEqual(cells[1], CGRect(x: 334, y: 0, width: 333, height: 500))
        XCTAssertEqual(cells[2], CGRect(x: 667, y: 0, width: 334, height: 500))
        XCTAssertEqual(cells[0].maxX, cells[1].minX)
        XCTAssertEqual(cells[1].maxX, cells[2].minX)
    }
```

- [ ] **Step 2: Tests laufen lassen — sie müssen fehlschlagen**

Run: `swift test --filter CropCalculatorTests`
Expected: Compile-Fehler „incorrect argument label" / kein passendes `cropRect(displaySize:configuration:)`.

- [ ] **Step 3: Grid-Berechnung implementieren**

In `Sources/ScreenFramerCore/CropCalculator.swift` innerhalb von `enum CropCalculator` ergänzen:

```swift
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
```

- [ ] **Step 4: Tests laufen lassen — sie müssen grün sein**

Run: `swift test`
Expected: alle Tests PASS (alte Position-Tests laufen weiter, bis Task 5 sie entfernt).

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenFramerCore/CropCalculator.swift Tests/ScreenFramerCoreTests/CropCalculatorTests.swift
git commit -m "feat: compute grid-based crop rects"
```

---

### Task 4: `ConfigStore` — Pfad, Seed-Anlage, Laden

**Files:**
- Create: `Sources/ScreenFramer/ConfigStore.swift`

**Interfaces:**
- Consumes: `ConfigurationParser.parse(yaml:)` aus Task 2
- Produces (für Task 5/6):
  - `final class ConfigStore` mit `let fileURL: URL`
  - `func loadCreatingIfMissing() throws -> [CropConfiguration]` — legt Ordner + Datei mit Seeds an, falls sie fehlt, und lädt
  - `func load() throws -> [CropConfiguration]` — lädt ohne anzulegen

Kein Unit-Test (dünne Datei-I/O im App-Target; die Logik dahinter ist in Core getestet). Verifikation manuell in Step 2.

- [ ] **Step 1: `ConfigStore` implementieren**

`Sources/ScreenFramer/ConfigStore.swift` anlegen:

```swift
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
```

- [ ] **Step 2: Bauen**

Run: `swift build`
Expected: Build ohne Fehler. *(Die Seed-Anlage lässt sich erst verifizieren, wenn der `StatusBarController` den `ConfigStore` benutzt — das prüft Task 5, Step 5.)*

- [ ] **Step 3: Commit**

```bash
git add Sources/ScreenFramer/ConfigStore.swift
git commit -m "feat: add ConfigStore with seeded config file"
```

---

### Task 5: App auf `CropConfiguration` umstellen (Menü, CaptureEngine, Overlay)

**Files:**
- Modify: `Sources/ScreenFramer/StatusBarController.swift`
- Modify: `Sources/ScreenFramer/CaptureEngine.swift`
- Modify: `Sources/ScreenFramerCore/CropCalculator.swift` (altes API entfernen)
- Modify: `Tests/ScreenFramerCoreTests/CropCalculatorTests.swift` (alte Tests entfernen)

**Interfaces:**
- Consumes: `CropConfiguration`, `CropCalculator.cropRect(displaySize:configuration:)`, `ConfigStore.loadCreatingIfMissing()`
- Produces (für Task 6):
  - `StatusBarController` hält `private let configStore = ConfigStore()`, `private var configurations: [CropConfiguration]`, `private var activeConfiguration: CropConfiguration?`
  - `private func switchConfiguration(to:on:)` — wechselt seamless (gleiche Pixelgröße) oder per Neustart
  - `CaptureEngine.start(displayID:configuration:)` und `CaptureEngine.update(configuration:)`

- [ ] **Step 1: `CaptureEngine` umstellen**

In `Sources/ScreenFramer/CaptureEngine.swift`:

`start(displayID:position:)` → Signatur und Aufruf ändern:

```swift
    func start(displayID: CGDirectDisplayID, configuration: CropConfiguration) async throws {
```

und darin `applyCrop(position: position, to: config)` ersetzen durch `applyCrop(configuration: configuration, to: config)`.

Die gespeicherte `SCStreamConfiguration`-Property heißt bisher `configuration` — sie kollidiert mit dem neuen Parameternamen. Property umbenennen in `private var streamConfiguration: SCStreamConfiguration?` und **alle** Zugriffe anpassen (in `start`, `stop` und im `SCStreamDelegate`).

`updatePosition(_:)` ersetzen durch:

```swift
    func update(configuration: CropConfiguration) async throws {
        guard let stream, let config = streamConfiguration else { return }
        applyCrop(configuration: configuration, to: config)
        try await stream.updateConfiguration(config)
    }
```

`applyCrop` ersetzen durch:

```swift
    private func applyCrop(
        configuration: CropConfiguration, to config: SCStreamConfiguration
    ) {
        let crop = CropCalculator.cropRect(
            displaySize: displaySize, configuration: configuration)
        config.sourceRect = crop
        config.width = Int(crop.width * scaleFactor)
        config.height = Int(crop.height * scaleFactor)
    }
```

- [ ] **Step 2: `StatusBarController` umstellen**

In `Sources/ScreenFramer/StatusBarController.swift`:

**Properties:** `private var position: CropPosition = .center` und `positionTitles` löschen, stattdessen:

```swift
    private let configStore = ConfigStore()
    private var configurations: [CropConfiguration] = []
    private var activeConfiguration: CropConfiguration?
```

**`init`:** nach dem Menü-Setup die Konfigurationen laden:

```swift
        do {
            configurations = try configStore.loadCreatingIfMissing()
        } catch {
            // Launch nicht blockieren — Alert erst nach dem App-Start
            DispatchQueue.main.async { [weak self] in
                self?.showError(
                    error, title: "Konfiguration konnte nicht geladen werden")
            }
        }
```

**`menuNeedsUpdate`:** die `positionTitles`-Schleife ersetzen durch:

```swift
        if configurations.isEmpty {
            let emptyItem = NSMenuItem(
                title: "Keine gültigen Konfigurationen", action: nil,
                keyEquivalent: "")
            menu.addItem(emptyItem)
        }
        for configuration in configurations {
            let item = NSMenuItem(
                title: configuration.name,
                action: #selector(startTransmission(_:)), keyEquivalent: "")
            item.target =
                (clickedDisplayID != nil && !clickedIsVirtual && !isStarting) ? self : nil
            item.representedObject = configuration.name
            item.state =
                (isRunning && configuration.name == activeConfiguration?.name)
                ? .on : .off
            menu.addItem(item)
        }
```

**`startTransmission`:** komplett ersetzen durch:

```swift
    // Klick auf eine Konfiguration: startet die Übertragung für den Monitor,
    // auf dem das Menü geöffnet wurde — bzw. wechselt nur die Konfiguration,
    // wenn genau dieser Monitor bereits übertragen wird.
    @objc private func startTransmission(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let newConfiguration = configurations.first(where: { $0.name == name }),
              let displayID = clickedDisplayID,
              displayID != virtualDisplayController.displayID,
              !isStarting else { return }

        if isRunning, displayID == activeDisplayID {
            guard newConfiguration != activeConfiguration else { return }
            switchConfiguration(to: newConfiguration, on: displayID)
            return
        }

        activeConfiguration = newConfiguration
        startCapture(on: displayID)
    }

    /// Wechselt die Konfiguration einer laufenden Übertragung. Bleibt die
    /// Pixelgröße des Ausschnitts gleich, wird nur der Stream umkonfiguriert;
    /// sonst muss der virtuelle Bildschirm neu erzeugt werden (Neustart).
    private func switchConfiguration(
        to newConfiguration: CropConfiguration, on displayID: CGDirectDisplayID
    ) {
        let previous = activeConfiguration
        activeConfiguration = newConfiguration
        guard let previous,
              cropPixelSize(for: displayID, configuration: previous)
                  == cropPixelSize(for: displayID, configuration: newConfiguration)
        else {
            startCapture(on: displayID)
            return
        }
        Task { @MainActor in
            do {
                try await self.captureEngine.update(configuration: newConfiguration)
                // Zwischenzeitliches Teardown (z. B. Stream-Fehler): kein
                // Overlay für eine beendete Übertragung wiederbeleben
                guard self.isRunning, self.activeDisplayID == displayID else { return }
                self.showFrameOverlay(for: displayID)
            } catch {
                self.activeConfiguration = previous
                self.showError(error, title: "Konfigurationswechsel fehlgeschlagen")
            }
        }
    }
```

**`startCapture`:** erste Zeilen anpassen — aus

```swift
    private func startCapture(on displayID: CGDirectDisplayID) {
        guard !isStarting else { return }
```

wird

```swift
    private func startCapture(on displayID: CGDirectDisplayID) {
        guard !isStarting, let configuration = activeConfiguration else { return }
```

und darin `cropPixelSize(for: displayID)` → `cropPixelSize(for: displayID, configuration: configuration)` sowie `try await self.captureEngine.start(displayID: displayID, position: self.position)` → `try await self.captureEngine.start(displayID: displayID, configuration: configuration)`.

**`cropPixelSize`:** ersetzen durch:

```swift
    /// Pixelgröße des Ausschnitts = Auflösung des virtuellen Bildschirms.
    private func cropPixelSize(
        for displayID: CGDirectDisplayID, configuration: CropConfiguration
    ) -> CGSize? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else { return nil }
        let crop = CropCalculator.cropRect(
            displaySize: screen.frame.size, configuration: configuration)
        let scale = screen.backingScaleFactor
        return CGSize(width: crop.width * scale, height: crop.height * scale)
    }
```

**`showFrameOverlay`:** ersetzen durch:

```swift
    /// Zeigt den Rahmen um den aktuellen Ausschnitt bzw. verschiebt ihn.
    private func showFrameOverlay(for displayID: CGDirectDisplayID) {
        guard let configuration = activeConfiguration,
              let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else { return }
        let crop = CropCalculator.cropRect(
            displaySize: screen.frame.size, configuration: configuration)
        if let overlay = frameOverlayController {
            overlay.move(to: crop, on: screen)
        } else {
            frameOverlayController = CropFrameOverlayController(cropRect: crop, on: screen)
        }
    }
```

- [ ] **Step 3: Altes API entfernen**

- In `Sources/ScreenFramerCore/CropCalculator.swift`: `enum CropPosition` und `cropRect(displaySize:position:)` löschen (`cocoaFrame(for:in:)` bleibt).
- In `Tests/ScreenFramerCoreTests/CropCalculatorTests.swift`: die sechs Position-Tests löschen (`testSuperUltrawideLeft`, `testSuperUltrawideCenter`, `testSuperUltrawideRight`, `testUltrawideCenter`, `testExact16to9IsFullDisplay`, `testNarrowerThan16to9UsesFullWidth`). Die `cocoaFrame`- und Grid-Tests bleiben.

- [ ] **Step 4: Tests und Build prüfen**

Run: `swift test`
Expected: alle Tests PASS, keine Referenzen mehr auf `CropPosition` (`grep -rn "CropPosition" Sources Tests` → leer).

- [ ] **Step 5: Manuell verifizieren**

```bash
rm -rf ~/.config/screen-framer
make restart
cat ~/.config/screen-framer/config.yaml
```

Erwartung: Die Config-Datei wurde mit dem Seed-Inhalt angelegt (Kommentare + drei Einträge). Dann manuell durchklicken:
1. Menüleisten-Icon → Menü zeigt „Links", „Mitte", „Rechts" (aus der Datei).
2. „Links" klicken → Übertragung startet, grüner Rahmen um die linke Monitorhälfte, virtueller Bildschirm zeigt die linke Hälfte.
3. „Rechts" klicken → nahtloser Wechsel (gleiche Pixelgröße, kein Neustart des virtuellen Bildschirms).
4. „Mitte" klicken → mittlere Hälfte.
5. „Übertragung stoppen" → Rahmen und virtueller Bildschirm verschwinden.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat: drive menu and capture from YAML configurations"
```

---

### Task 6: Menüeinträge „Konfigurationsdatei öffnen" und „Konfiguration neu laden"

**Files:**
- Modify: `Sources/ScreenFramer/StatusBarController.swift`

**Interfaces:**
- Consumes: `ConfigStore.load()`, `configStore.fileURL`, `switchConfiguration(to:on:)`, `teardown()` aus Task 5
- Produces: Menüeinträge + `@objc`-Actions `openConfigFile`, `reloadConfig`

- [ ] **Step 1: Menüeinträge ergänzen**

In `menuNeedsUpdate`, direkt **vor** dem letzten Block (`menu.addItem(.separator())` + „Beenden"):

```swift
        menu.addItem(.separator())
        let openItem = NSMenuItem(
            title: "Konfigurationsdatei öffnen",
            action: #selector(openConfigFile), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        let reloadItem = NSMenuItem(
            title: "Konfiguration neu laden",
            action: #selector(reloadConfig), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)
```

- [ ] **Step 2: Actions implementieren**

In `StatusBarController` (z. B. nach `stopCapture`):

```swift
    /// Öffnet die Config-Datei im Standardprogramm für YAML-Dateien —
    /// identisch zum Doppelklick im Finder.
    @objc private func openConfigFile() {
        NSWorkspace.shared.open(configStore.fileURL)
    }

    // Liest die Config-Datei neu ein. Bei Fehlern bleibt die zuletzt
    // gültige Liste aktiv. Für eine laufende Übertragung gilt: aktive
    // Konfiguration (per Name) unverändert → weiterlaufen; Geometrie
    // geändert → Wechsel/Neustart; gelöscht → stoppen.
    @objc private func reloadConfig() {
        do {
            configurations = try configStore.load()
        } catch {
            showError(error, title: "Konfiguration konnte nicht geladen werden")
            return
        }

        guard isRunning, let active = activeConfiguration else { return }
        guard let updated = configurations.first(where: { $0.name == active.name })
        else {
            // Aktive Konfiguration wurde entfernt → Übertragung stoppen
            Task { @MainActor in await self.teardown() }
            return
        }
        guard updated != active else { return }
        if let displayID = activeDisplayID {
            switchConfiguration(to: updated, on: displayID)
        } else {
            activeConfiguration = updated
        }
    }
```

- [ ] **Step 3: Bauen und Tests**

Run: `swift test && make build`
Expected: Tests PASS, Build ohne Fehler.

- [ ] **Step 4: Manuell verifizieren**

```bash
make restart
```

Manuell durchspielen:
1. **Öffnen:** „Konfigurationsdatei öffnen" → Datei öffnet sich im Standard-Editor (wie Finder-Doppelklick).
2. **Reload ohne Übertragung:** In der Datei eine vierte Konfiguration ergänzen (z. B. `- name: Oben links` mit `grid: {columns: 2, rows: 2}`), speichern, „Konfiguration neu laden" → Menü zeigt den neuen Eintrag; klicken → Viertel oben links wird übertragen.
3. **Reload mit geänderter Geometrie:** Während „Links" überträgt, in der Datei bei „Links" `columns: 3` setzen, neu laden → Übertragung startet neu mit dem linken Drittel.
4. **Reload mit gelöschtem Eintrag:** Während „Links" überträgt, den Eintrag „Links" löschen, neu laden → Übertragung stoppt.
5. **Kaputtes YAML:** `columns: abc` eintragen, neu laden → Alert mit Fehlermeldung; Menü zeigt weiterhin die alte Liste; eine laufende Übertragung läuft weiter.
6. Datei wieder in einen sauberen Zustand bringen (Änderungen von 2–5 zurücknehmen).

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenFramer/StatusBarController.swift
git commit -m "feat: add menu items to open and reload the config file"
```

import XCTest
@testable import ScreenFramerCore

final class CropCalculatorTests: XCTestCase {

    // 32:9-Monitor (zuhause): 5120×1440 → Ausschnitt 2560×1440
    func testSuperUltrawideLeft() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 5120, height: 1440), position: .left)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 2560, height: 1440))
    }

    func testSuperUltrawideCenter() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 5120, height: 1440), position: .center)
        XCTAssertEqual(rect, CGRect(x: 1280, y: 0, width: 2560, height: 1440))
    }

    func testSuperUltrawideRight() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 5120, height: 1440), position: .right)
        XCTAssertEqual(rect, CGRect(x: 2560, y: 0, width: 2560, height: 1440))
    }

    // 21:9-Monitor (Office): 2560×1080 → Ausschnitt 1920×1080
    func testUltrawideCenter() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 2560, height: 1080), position: .center)
        XCTAssertEqual(rect, CGRect(x: 320, y: 0, width: 1920, height: 1080))
    }

    // Monitor ist bereits 16:9 → Ausschnitt = ganzer Monitor
    func testExact16to9IsFullDisplay() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 1920, height: 1080), position: .center)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    // Monitor schmaler als 16:9 → volle Breite, keine negative x-Position
    func testNarrowerThan16to9UsesFullWidth() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 1024, height: 1440), position: .right)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 1024, height: 1440))
    }

    // MARK: - cocoaFrame(for:in:)

    // Monitor am globalen Ursprung, Ausschnitt volle Höhe → identische Werte
    func testCocoaFrameFullHeightAtOrigin() {
        let frame = CropCalculator.cocoaFrame(
            for: CGRect(x: 1280, y: 0, width: 2560, height: 1440),
            in: CGRect(x: 0, y: 0, width: 5120, height: 1440))
        XCTAssertEqual(frame, CGRect(x: 1280, y: 0, width: 2560, height: 1440))
    }

    // Monitor mit globalem Offset (z. B. zweiter Monitor im Arrangement)
    func testCocoaFrameWithScreenOffset() {
        let frame = CropCalculator.cocoaFrame(
            for: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            in: CGRect(x: 100, y: 50, width: 2560, height: 1080))
        XCTAssertEqual(frame, CGRect(x: 100, y: 50, width: 1920, height: 1080))
    }

    // Monitor links unterhalb des Hauptmonitors (negativer globaler Ursprung)
    func testCocoaFrameWithNegativeScreenOrigin() {
        let frame = CropCalculator.cocoaFrame(
            for: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            in: CGRect(x: -1920, y: -280, width: 1920, height: 1080))
        XCTAssertEqual(frame, CGRect(x: -1920, y: -280, width: 1920, height: 1080))
    }

    // Teilhöhe: beweist die y-Spiegelung (oben-links → unten-links)
    func testCocoaFrameFlipsYForPartialHeight() {
        let frame = CropCalculator.cocoaFrame(
            for: CGRect(x: 0, y: 100, width: 800, height: 450),
            in: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        XCTAssertEqual(frame, CGRect(x: 0, y: 450, width: 800, height: 450))
    }

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
}

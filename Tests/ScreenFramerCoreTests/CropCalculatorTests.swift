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
}

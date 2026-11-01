import XCTest
@testable import Thockbox

final class TonePadTests: XCTestCase {
    func testStepStaysInRangeAndReturnsToZero() {
        XCTAssertEqual(TonePadView.step(0.95, by: 0.1), 1)
        XCTAssertEqual(TonePadView.step(-1, by: -0.1), -1)
        var value: Float = 0
        for _ in 0..<7 { value = TonePadView.step(value, by: 0.1) }
        for _ in 0..<7 { value = TonePadView.step(value, by: -0.1) }
        XCTAssertEqual(value, 0)
    }

    func testDescription() {
        XCTAssertEqual(TonePadView.describe(x: 0, y: 0), "neutral, normal pitch")
        XCTAssertEqual(TonePadView.describe(x: 0.4, y: -0.2), "40% brighter, pitch 20% lower")
        XCTAssertEqual(TonePadView.describe(x: -1, y: 1), "100% darker, pitch 100% higher")
    }
}

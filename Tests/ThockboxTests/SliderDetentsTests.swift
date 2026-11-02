import XCTest
@testable import Thockbox

final class SliderDetentsTests: XCTestCase {
    private func crossed(_ old: Double, _ new: Double, _ range: ClosedRange<Double> = 0...1, step: Double = 0.1) -> Bool {
        SliderDetents.crossed(from: old, to: new, in: range, step: step)
    }

    func testVolumeTapsEveryTenPercent() {
        XCTAssertTrue(crossed(0.48, 0.52), "passes 50%")
        XCTAssertFalse(crossed(0.51, 0.55), "between notches")
        XCTAssertTrue(crossed(0.55, 0.62))
        XCTAssertTrue(crossed(0.62, 0.58), "moving down too")
    }

    func testTheEndsTap() {
        XCTAssertTrue(crossed(0.05, 0))
        XCTAssertTrue(crossed(0.97, 1))
        XCTAssertFalse(crossed(1, 1), "no movement, no tap")
    }

    /// Tone sliders have one notch, at the middle.
    func testToneTapsAtTheCenter() {
        XCTAssertTrue(crossed(-0.1, 0.1, -1...1, step: 1))
        XCTAssertTrue(crossed(-0.1, 0, -1...1, step: 1), "landing on it")
        XCTAssertFalse(crossed(0.2, 0.5, -1...1, step: 1))
    }
}

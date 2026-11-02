import XCTest
@testable import Thockbox

final class TypingDynamicsTests: XCTestCase {
    func testFastIsLighterSlowIsFull() {
        XCTAssertEqual(TypingDynamics.velocity(gap: 0.03), 0.8, "a fast burst")
        XCTAssertEqual(TypingDynamics.velocity(gap: 0.06), 0.8)
        XCTAssertEqual(TypingDynamics.velocity(gap: 0.35), 1)
        XCTAssertEqual(TypingDynamics.velocity(gap: 2), 1, "a pause")
        let typical = TypingDynamics.velocity(gap: 0.17) // ~70 words per minute
        XCTAssertGreaterThan(typical, 0.85)
        XCTAssertLessThan(typical, 0.9)
    }

    func testFirstPressIsFullAndReleasesMatchTheirPress() {
        var dynamics = TypingDynamics()
        XCTAssertEqual(dynamics.press(0, at: 10), 1, "nothing to compare with yet")
        let fast = dynamics.press(1, at: 10.05)
        XCTAssertEqual(fast, 0.8)
        XCTAssertEqual(dynamics.release(0), 1, "released at the strength it was pressed")
        XCTAssertEqual(dynamics.release(1), fast)
        XCTAssertEqual(dynamics.release(1), 1, "a release without a press plays normally")
    }
}

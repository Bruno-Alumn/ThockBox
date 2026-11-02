import XCTest
@testable import Thockbox

final class ScrollTickerTests: XCTestCase {
    func testTrackpadTicksOncePerStepOfTravel() {
        var ticker = ScrollTicker()
        var ticks = 0
        // 360 px in 10 px events over a second: one tick per 36 px.
        for i in 0..<36 where ticker.scroll(delta: -10, precise: true, at: Double(i) / 36) {
            ticks += 1
        }
        XCTAssertEqual(ticks, 10)
    }

    func testEachWheelStepTicks() {
        var ticker = ScrollTicker()
        XCTAssertTrue(ticker.scroll(delta: 1, precise: false, at: 0))
        XCTAssertTrue(ticker.scroll(delta: -1, precise: false, at: 0.1))
        XCTAssertFalse(ticker.scroll(delta: 0, precise: false, at: 0.2), "a sideways scroll")
    }

    /// A fast swipe doesn't turn into a buzz.
    func testTicksAreRateLimited() {
        var ticker = ScrollTicker()
        var ticks = 0
        for i in 0..<100 where ticker.scroll(delta: 1, precise: false, at: Double(i) / 1000) {
            ticks += 1
        }
        XCTAssertEqual(ticks, 3, "100 ms at 25 ticks a second")
    }
}

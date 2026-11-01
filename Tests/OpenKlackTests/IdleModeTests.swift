import XCTest
@testable import OpenKlack

final class IdleModeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testZeroTimeoutDisablesIdleMode() {
        let mode = IdleMode(now: start)
        XCTAssertFalse(mode.isIdle(at: start.addingTimeInterval(86_400), timeoutMinutes: 0))
    }

    func testIdleAtConfiguredTimeout() {
        let mode = IdleMode(now: start)
        XCTAssertFalse(mode.isIdle(at: start.addingTimeInterval(299), timeoutMinutes: 5))
        XCTAssertTrue(mode.isIdle(at: start.addingTimeInterval(300), timeoutMinutes: 5))
    }

    func testActivityRestartsTimeout() {
        var mode = IdleMode(now: start)
        mode.recordActivity(now: start.addingTimeInterval(240))
        XCTAssertFalse(mode.isIdle(at: start.addingTimeInterval(539), timeoutMinutes: 5))
        XCTAssertTrue(mode.isIdle(at: start.addingTimeInterval(540), timeoutMinutes: 5))
    }
}

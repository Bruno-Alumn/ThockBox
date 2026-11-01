import XCTest
@testable import OpenKlack

final class KeystrokeStatsTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "OpenKlackTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func day(_ s: String, hour: Int = 12) -> Date {
        let c = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: .current,
                               year: Int(s.prefix(4)), month: Int(s.dropFirst(5).prefix(2)),
                               day: Int(s.suffix(2)), hour: hour)
        return c.date!
    }

    func testCountsTodayAndTotal() {
        var stats = KeystrokeStats(defaults: defaults, now: day("2026-11-01"))
        for _ in 0..<3 { stats.record(now: day("2026-11-01")) }
        XCTAssertEqual(stats.today, 3)
        XCTAssertEqual(stats.total, 3)
    }

    func testNewDayResetsTodayButNotTotal() {
        var stats = KeystrokeStats(defaults: defaults, now: day("2026-11-01"))
        stats.record(now: day("2026-11-01", hour: 23))
        stats.record(now: day("2026-11-02", hour: 0))
        XCTAssertEqual(stats.today, 1)
        XCTAssertEqual(stats.total, 2)
    }

    func testLaunchOnALaterDayDoesNotShowYesterdaysCount() {
        var stats = KeystrokeStats(defaults: defaults, now: day("2026-11-01"))
        for _ in 0..<5 { stats.record(now: day("2026-11-01")) }
        stats.flush()

        let relaunched = KeystrokeStats(defaults: defaults, now: day("2026-11-03"))
        XCTAssertEqual(relaunched.today, 0)
        XCTAssertEqual(relaunched.total, 5)
    }

    func testRolloverWithoutKeystrokes() {
        var stats = KeystrokeStats(defaults: defaults, now: day("2026-11-01"))
        stats.record(now: day("2026-11-01"))
        stats.rollOver(now: day("2026-11-02"))   // midnight notification
        XCTAssertEqual(stats.today, 0)
        XCTAssertEqual(stats.total, 1)
    }

    func testCountsSurviveARelaunchOnTheSameDay() {
        var stats = KeystrokeStats(defaults: defaults, now: day("2026-11-01"))
        for _ in 0..<7 { stats.record(now: day("2026-11-01")) }
        stats.flush()
        let relaunched = KeystrokeStats(defaults: defaults, now: day("2026-11-01", hour: 18))
        XCTAssertEqual(relaunched.today, 7)
        XCTAssertEqual(relaunched.total, 7)
    }
}

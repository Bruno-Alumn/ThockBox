import XCTest
@testable import Thockbox

final class KeystrokeStatsTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "ThockboxTests.\(UUID().uuidString)"
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

    func testCSVListsDaysOldestFirstWithToday() {
        var stats = KeystrokeStats(defaults: defaults, now: day("2026-11-01"))
        for _ in 0..<3 { stats.record(now: day("2026-11-01")) }
        for _ in 0..<2 { stats.record(now: day("2026-11-03")) }
        XCTAssertEqual(stats.csv(), "date,keystrokes\n2026-11-01,3\n2026-11-03,2\n")
    }

    /// 300 keys over a minute of steady typing is 60 words a minute; a
    /// long pause in the middle doesn't drag it down.
    func testWordsPerMinuteLeavesOutPauses() {
        var stats = KeystrokeStats(defaults: defaults, now: day("2026-11-01"))
        let start = day("2026-11-01")
        for i in 0..<150 { stats.record(now: start.addingTimeInterval(Double(i) * 0.2)) }
        let later = start.addingTimeInterval(600)   // a ten-minute break
        for i in 0..<150 { stats.record(now: later.addingTimeInterval(Double(i) * 0.2)) }
        XCTAssertEqual(stats.wordsPerMinute ?? 0, 60, accuracy: 1)
    }

    func testNoSpeedUntilThereIsEnoughTyping() {
        var stats = KeystrokeStats(defaults: defaults, now: day("2026-11-01"))
        for i in 0..<20 { stats.record(now: day("2026-11-01").addingTimeInterval(Double(i) * 0.2)) }
        XCTAssertNil(stats.wordsPerMinute)
    }

    func testTypingTimeResetsWithTheDay() {
        var stats = KeystrokeStats(defaults: defaults, now: day("2026-11-01"))
        for i in 0..<300 { stats.record(now: day("2026-11-01").addingTimeInterval(Double(i) * 0.2)) }
        XCTAssertNotNil(stats.wordsPerMinute)
        stats.record(now: day("2026-11-02"))
        XCTAssertEqual(stats.typingSeconds, 0)
    }

    func testBestDayAndDailyAverage() {
        var stats = KeystrokeStats(defaults: defaults, now: day("2026-11-01"))
        XCTAssertNil(stats.bestDay)
        XCTAssertNil(stats.dailyAverage)
        for _ in 0..<100 { stats.record(now: day("2026-11-01")) }
        for _ in 0..<300 { stats.record(now: day("2026-11-02")) }
        for _ in 0..<50 { stats.record(now: day("2026-11-03")) }
        XCTAssertEqual(stats.bestDay?.date, "2026-11-02")
        XCTAssertEqual(stats.bestDay?.count, 300)
        XCTAssertEqual(stats.dailyAverage, 200, "finished days only, not today's 50")
    }

    func testStreakCountsDaysInARow() {
        var stats = KeystrokeStats(defaults: defaults, now: day("2026-11-01"))
        for d in ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-05", "2026-11-06"] {
            stats.record(now: day(d))
        }
        XCTAssertEqual(stats.streak(now: day("2026-11-06")), 2, "the gap on the 4th ends it")
        stats.record(now: day("2026-11-07"))
        XCTAssertEqual(stats.streak(now: day("2026-11-07")), 3)
        stats.flush()   // as at quit
        let nextMorning = KeystrokeStats(defaults: defaults, now: day("2026-11-08", hour: 7))
        XCTAssertEqual(nextMorning.streak(now: day("2026-11-08", hour: 7)), 3, "not lost before typing today")
        XCTAssertEqual(nextMorning.streak(now: day("2026-11-10")), 0, "a day missed")
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
    func testFinishedDaysAreKeptForTheWeekChart() {
        var stats = KeystrokeStats(defaults: defaults, now: day("2026-11-01"))
        for _ in 0..<5 { stats.record(now: day("2026-11-01")) }
        for _ in 0..<2 { stats.record(now: day("2026-11-03")) }
        stats.flush()

        let week = KeystrokeStats(defaults: defaults, now: day("2026-11-03")).lastWeek(now: day("2026-11-03"))
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.map(\.count), [0, 0, 0, 0, 5, 0, 2], "Nov 1, an idle Nov 2, then today")
    }

    func testHistoryDropsDaysOlderThanAMonth() {
        var stats = KeystrokeStats(defaults: defaults, now: day("2026-09-01"))
        stats.record(now: day("2026-09-01"))
        stats.record(now: day("2026-11-01"))
        let saved = defaults.dictionary(forKey: "statsHistory") as? [String: Int] ?? [:]
        XCTAssertNil(saved["2026-09-01"])
    }

}

final class StatsStoreTests: XCTestCase {
    func testMenuCountRefreshesOnceAfterABurst() {
        let suite = "ThockboxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = StatsStore(defaults: defaults)
        var publishes = 0
        let sub = store.objectWillChange.sink { publishes += 1 }
        defer { sub.cancel() }

        for _ in 0..<50 { store.record() }
        XCTAssertEqual(store.shown.today, 0, "no re-render per key press")

        let refreshed = expectation(description: "refreshed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { refreshed.fulfill() }
        wait(for: [refreshed], timeout: 2)
        XCTAssertEqual(store.shown.today, 50)
        XCTAssertEqual(publishes, 1, "one refresh for the whole burst")
    }


    func testChartBarsReadAsKeystrokes() {
        XCTAssertEqual(KeystrokeChart.spoken(0), "0 keystrokes")
        XCTAssertEqual(KeystrokeChart.spoken(1), "1 keystroke")
        XCTAssertEqual(KeystrokeChart.spoken(1234), 1234.formatted() + " keystrokes")
    }
}

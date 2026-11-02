import XCTest
@testable import Thockbox

final class CalendarMonitorTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(from start: TimeInterval, to end: TimeInterval,
                       allDay: Bool = false, free: Bool = false) -> CalendarMonitor.Event {
        .init(start: now.addingTimeInterval(start * 60), end: now.addingTimeInterval(end * 60),
              isAllDay: allDay, isFree: free)
    }

    func testAMeetingHappeningNowMutes() {
        XCTAssertTrue(CalendarMonitor.isBusy([event(from: -10, to: 20)], at: now))
        XCTAssertTrue(CalendarMonitor.isBusy([event(from: 0, to: 30)], at: now), "starts right now")
        XCTAssertFalse(CalendarMonitor.isBusy([event(from: -30, to: 0)], at: now), "just ended")
        XCTAssertFalse(CalendarMonitor.isBusy([event(from: 5, to: 30)], at: now), "not yet")
    }

    /// Holidays, trips and "free" or declined events don't take up the time.
    func testAllDayAndFreeEventsDont() {
        XCTAssertFalse(CalendarMonitor.isBusy([event(from: -600, to: 800, allDay: true)], at: now))
        XCTAssertFalse(CalendarMonitor.isBusy([event(from: -10, to: 20, free: true)], at: now))
    }

    func testNextCheckIsTheNextEdgeOrFifteenMinutes() {
        XCTAssertEqual(CalendarMonitor.nextCheck([event(from: -10, to: 5)], after: now),
                       now.addingTimeInterval(5 * 60), "the meeting ends")
        XCTAssertEqual(CalendarMonitor.nextCheck([event(from: 3, to: 60)], after: now),
                       now.addingTimeInterval(3 * 60), "the next one starts")
        XCTAssertEqual(CalendarMonitor.nextCheck([event(from: 120, to: 180)], after: now),
                       now.addingTimeInterval(15 * 60), "nothing soon")
        XCTAssertEqual(CalendarMonitor.nextCheck([event(from: 3, to: 60, free: true)], after: now),
                       now.addingTimeInterval(15 * 60), "free events don't matter")
    }

    func testCalendarChoiceSummary() {
        let calendars = ["work", "home", "holidays"].map {
            CalendarMonitor.CalendarInfo(id: $0, title: $0, account: "iCloud")
        }
        XCTAssertEqual(CalendarMonitor.summary(calendars, ignoring: []), "All")
        XCTAssertEqual(CalendarMonitor.summary(calendars, ignoring: ["holidays"]), "2 of 3")
        XCTAssertEqual(CalendarMonitor.summary(calendars, ignoring: ["work", "home", "holidays"]), "None")
        XCTAssertEqual(CalendarMonitor.summary(calendars, ignoring: ["gone"]), "All",
                       "a removed calendar doesn't count against the others")
    }

    func testIgnoredCalendarsAreSaved() {
        let suite = "ThockboxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.readsCalendars = false
        state.ignoredCalendarIDs = ["holidays"]
        XCTAssertEqual(AppState(defaults: defaults).ignoredCalendarIDs, ["holidays"])
    }
}

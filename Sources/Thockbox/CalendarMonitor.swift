import EventKit
import AppKit

/// Reports whether a calendar event is happening now, so sounds can stay
/// quiet during meetings. Reads the calendars macOS already has (iCloud,
/// Google, Exchange) after the user allows it once; nothing leaves the Mac.
///
/// Checks again when an event starts or ends, when calendars change, and at
/// least every 15 minutes, so it never polls tightly.
final class CalendarMonitor {
    /// The parts of an event that decide whether it mutes.
    struct Event {
        let start: Date
        let end: Date
        let isAllDay: Bool
        /// Marked free, or declined: the time isn't really taken.
        let isFree: Bool
    }

    enum Access { case unknown, granted, denied }

    private(set) var inEvent = false
    private(set) var access = Access.unknown
    private let store = EKEventStore()
    private let onChange: (Bool) -> Void
    private let onAccess: (Access) -> Void
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(onChange: @escaping (Bool) -> Void, onAccess: @escaping (Access) -> Void) {
        self.onChange = onChange
        self.onAccess = onAccess
        requestAccess()
    }

    deinit {
        timer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    private func requestAccess() {
        let done: (Bool, Error?) -> Void = { [weak self] granted, _ in
            DispatchQueue.main.async { self?.accessDecided(granted) }
        }
        if #available(macOS 14, *) {
            store.requestFullAccessToEvents(completion: done)
        } else {
            store.requestAccess(to: .event, completion: done)
        }
    }

    private func accessDecided(_ granted: Bool) {
        access = granted ? .granted : .denied
        onAccess(access)
        guard granted else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.check() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.check() })
        check()
    }

    private func check(now: Date = Date()) {
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-86_400),
                                                 end: now.addingTimeInterval(86_400), calendars: nil)
        let events = store.events(matching: predicate).map(Self.event)
        let busy = Self.isBusy(events, at: now)
        if busy != inEvent {
            inEvent = busy
            onChange(busy)
        }
        timer?.invalidate()
        let next = Self.nextCheck(events, after: now)
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in self?.check() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private static func event(_ event: EKEvent) -> Event {
        let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
        return Event(start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                     isFree: event.availability == .free || declined)
    }

    /// An event mutes while it's on, unless it lasts all day (a holiday, a
    /// trip) or doesn't take up the time.
    static func counts(_ event: Event) -> Bool {
        !event.isAllDay && !event.isFree
    }

    static func isBusy(_ events: [Event], at now: Date) -> Bool {
        events.contains { counts($0) && $0.start <= now && now < $0.end }
    }

    /// The next time the answer can change: an event starting or ending,
    /// and never more than 15 minutes away (calendars can sync late).
    static func nextCheck(_ events: [Event], after now: Date) -> Date {
        let limit = now.addingTimeInterval(15 * 60)
        let edges = events.filter(counts).flatMap { [$0.start, $0.end] }.filter { $0 > now }
        return min(edges.min() ?? limit, limit)
    }
}

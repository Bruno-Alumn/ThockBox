import Foundation

/// Today / all-time keystroke counts, persisted to UserDefaults. A value
/// type so AppState publishes one change per keystroke, not one per counter.
struct KeystrokeStats {
    private(set) var today: Int
    private(set) var total: Int
    private var stamp: String
    private let defaults: UserDefaults

    init(defaults: UserDefaults, now: Date = Date()) {
        self.defaults = defaults
        today = defaults.integer(forKey: "statsToday")
        total = defaults.integer(forKey: "statsTotal")
        stamp = defaults.string(forKey: "statsTodayStamp") ?? ""
        rollOver(now: now)
    }

    /// Zero "today" once the date has moved past the saved stamp, so a count
    /// from yesterday isn't shown as today's.
    mutating func rollOver(now: Date = Date()) {
        let day = Self.dayStamp(now)
        guard day != stamp else { return }
        stamp = day
        today = 0
        defaults.set(day, forKey: "statsTodayStamp")
        defaults.set(0, forKey: "statsToday")
    }

    mutating func record(now: Date = Date()) {
        rollOver(now: now)
        today += 1
        total += 1
        // UserDefaults writes hit an in-memory cache; persist every N strokes
        // to avoid two change notifications per keypress. flush() covers the
        // remainder at quit.
        if today % 20 == 0 {
            flush()
        }
    }

    func flush() {
        defaults.set(today, forKey: "statsToday")
        defaults.set(total, forKey: "statsTotal")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayStamp(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}

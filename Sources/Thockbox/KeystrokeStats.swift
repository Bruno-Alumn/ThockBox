import Foundation

/// Today / all-time keystroke counts, persisted to UserDefaults. A value
/// type so AppState publishes one change per keystroke, not one per counter.
struct KeystrokeStats {
    private(set) var today: Int
    private(set) var total: Int
    private var stamp: String
    /// Finished days, "yyyy-MM-dd" → count. Kept for 30 days.
    private var history: [String: Int]
    private let defaults: UserDefaults

    init(defaults: UserDefaults, now: Date = Date()) {
        self.defaults = defaults
        today = defaults.integer(forKey: "statsToday")
        total = defaults.integer(forKey: "statsTotal")
        stamp = defaults.string(forKey: "statsTodayStamp") ?? ""
        history = defaults.dictionary(forKey: "statsHistory") as? [String: Int] ?? [:]
        rollOver(now: now)
    }

    /// Zero "today" once the date has moved past the saved stamp, so a count
    /// from yesterday isn't shown as today's.
    mutating func rollOver(now: Date = Date()) {
        let day = Self.dayStamp(now)
        guard day != stamp else { return }
        if !stamp.isEmpty, today > 0 {
            history[stamp] = today
            let cutoff = Self.dayStamp(now.addingTimeInterval(-30 * 86_400))
            history = history.filter { $0.key >= cutoff }
            defaults.set(history, forKey: "statsHistory")
        }
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

    struct Day: Identifiable {
        let date: Date
        let count: Int
        var id: Date { date }
    }

    /// The last seven days, oldest first, ending with today. Days without
    /// typing count as zero.
    func lastWeek(now: Date = Date()) -> [Day] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: start) else { return nil }
            let key = Self.dayStamp(date)
            return Day(date: date, count: key == stamp ? today : history[key] ?? 0)
        }
    }

    /// Every day kept (the last 30 plus today) as CSV, oldest first:
    /// "date,keystrokes" with ISO dates, for a spreadsheet.
    func csv() -> String {
        var days = history
        if !stamp.isEmpty { days[stamp] = today }
        let rows = days.sorted { $0.key < $1.key }.map { "\($0.key),\($0.value)" }
        return (["date,keystrokes"] + rows).joined(separator: "\n") + "\n"
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

/// Keeps the counts out of AppState and publishes them at most twice a
/// second. Each change to the counts text re-lays out the whole menu, even
/// while it's closed: publishing per key cost ~2.6 ms CPU per key vs ~0.2.
final class StatsStore: ObservableObject {
    /// What the menu shows; trails `stats` by up to `refreshDelay`.
    @Published private(set) var shown: KeystrokeStats
    private var stats: KeystrokeStats
    private var refreshPending = false
    private let refreshDelay = 0.5

    init(defaults: UserDefaults) {
        stats = KeystrokeStats(defaults: defaults)
        shown = stats
    }

    func record() {
        stats.record()
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + refreshDelay) { [weak self] in
            guard let self else { return }
            refreshPending = false
            shown = stats
        }
    }

    func rollOver() {
        stats.rollOver()
        shown = stats
    }

    func flush() { stats.flush() }
}

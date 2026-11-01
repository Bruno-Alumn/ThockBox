import Foundation

struct IdleMode {
    private(set) var lastActivity: Date

    init(now: Date = Date()) {
        lastActivity = now
    }

    mutating func recordActivity(now: Date = Date()) {
        lastActivity = now
    }

    func isIdle(at now: Date = Date(), timeoutMinutes: Int) -> Bool {
        guard timeoutMinutes > 0 else { return false }
        return now.timeIntervalSince(lastActivity) >= TimeInterval(timeoutMinutes * 60)
    }
}

import Foundation

/// Turns scrolling into notches, like a mouse wheel with detents: one tick
/// per wheel step, or per `pixelsPerTick` of trackpad travel, and never
/// faster than `minInterval` so a fast swipe doesn't become a buzz.
struct ScrollTicker {
    static let pixelsPerTick = 36.0
    static let minInterval = 1.0 / 25

    private var travel = 0.0
    private var lastTick = -Double.infinity

    /// `precise` is a trackpad or Magic Mouse (pixel deltas); otherwise each
    /// event is one wheel step. Returns whether to tick now.
    mutating func scroll(delta: Double, precise: Bool, at time: TimeInterval) -> Bool {
        if precise {
            travel += abs(delta)
            guard travel >= Self.pixelsPerTick else { return false }
            travel = travel.truncatingRemainder(dividingBy: Self.pixelsPerTick)
        } else if delta == 0 {
            return false
        }
        guard time - lastTick >= Self.minInterval else { return false }
        lastTick = time
        return true
    }
}

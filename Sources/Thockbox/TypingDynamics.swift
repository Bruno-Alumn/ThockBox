import Foundation

/// How hard a key seems to be pressed, from the typing rhythm. Fast bursts
/// are struck lighter and slow, deliberate presses fuller, as on a real
/// board, so a run of keys doesn't come out at one flat level. Kept subtle:
/// at most about -2 dB.
struct TypingDynamics {
    /// Gain for a press at or under this gap from the previous one.
    static let lightest: Float = 0.8
    static let fastGap: TimeInterval = 0.06
    /// At or over this gap, a press plays at full gain.
    static let slowGap: TimeInterval = 0.35

    private var lastPress: TimeInterval?
    /// Per held key, so its release matches its press.
    private var held: [UInt16: Float] = [:]

    static func velocity(gap: TimeInterval) -> Float {
        let t = Float((gap - fastGap) / (slowGap - fastGap))
        return lightest + (1 - lightest) * min(max(t, 0), 1)
    }

    /// `now` is seconds on any steady clock (the app uses system uptime).
    mutating func press(_ keycode: UInt16, at now: TimeInterval) -> Float {
        let velocity = lastPress.map { Self.velocity(gap: now - $0) } ?? 1
        lastPress = now
        held[keycode] = velocity
        return velocity
    }

    /// The velocity its press had, or nil if no press was heard (it went
    /// down in a password field, or while muted): then the release is silent
    /// too, not a lone click.
    mutating func release(_ keycode: UInt16) -> Float? {
        held.removeValue(forKey: keycode)
    }
}

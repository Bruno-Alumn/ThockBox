import AppKit

/// What VoiceOver says for controls whose raw value means nothing spoken:
/// a -1...1 tone slider at 0 would otherwise read as "50%".
enum SpokenValue {
    static func percent(_ value: Float, of maximum: Float = 1) -> String {
        "\(Int((value / maximum * 100).rounded()))%"
    }

    /// "Neutral", "30% brighter", "20% darker" for a value in -1...1.
    static func direction(_ value: Float, up: String, down: String) -> String {
        let percent = Int((abs(value) * 100).rounded())
        guard percent > 0 else { return "Neutral" }
        return "\(percent)% \(value > 0 ? up : down)"
    }
}

extension Shortcut {
    /// "Control Command K": the shortcut as words, for VoiceOver.
    var spoken: String {
        let names: [(NSEvent.ModifierFlags, String)] = [(.control, "Control"), (.option, "Option"),
                                                         (.shift, "Shift"), (.command, "Command")]
        let keyNames = ["↩": "Return", "⇥": "Tab", "⌫": "Delete", "⌦": "Forward Delete",
                        "←": "Left Arrow", "→": "Right Arrow", "↓": "Down Arrow", "↑": "Up Arrow",
                        "↖": "Home", "↘": "End", "⇞": "Page Up", "⇟": "Page Down"]
        return (names.filter { flags.contains($0.0) }.map(\.1) + [keyNames[key] ?? key]).joined(separator: " ")
    }
}

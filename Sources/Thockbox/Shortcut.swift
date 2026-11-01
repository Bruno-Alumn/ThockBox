import AppKit

/// The key combination that turns sounds on and off.
struct Shortcut: Codable, Equatable {
    let keyCode: UInt16
    /// NSEvent.ModifierFlags raw value, limited to ⌃ ⌥ ⇧ ⌘.
    let modifiers: UInt
    /// The key as shown, e.g. "K" or "Space".
    let key: String

    static let standard = Shortcut(keyCode: 40, flags: [.control, .command], key: "K")
    private static let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = flags.intersection(Self.relevant).rawValue
        self.key = key
    }

    /// A recorded key press. nil without ⌘, ⌃ or ⌥: a plain or shifted key
    /// would fire while typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.relevant)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        self.init(keyCode: event.keyCode, flags: flags, key: Self.name(for: event))
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// Exact match: ⌃⌘K doesn't fire for ⌃⇧⌘K.
    func matches(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == self.keyCode && flags.intersection(Self.relevant) == self.flags
    }

    /// "⌃⌘K", modifiers in the order macOS menus use.
    var display: String {
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { flags.contains($0.0) }.map(\.1).joined() + key
    }

    private static let specialKeys: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func name(for event: NSEvent) -> String {
        if let special = specialKeys[event.keyCode] { return special }
        let characters = event.charactersIgnoringModifiers?.uppercased() ?? ""
        return characters.isEmpty ? "Key \(event.keyCode)" : characters
    }
}

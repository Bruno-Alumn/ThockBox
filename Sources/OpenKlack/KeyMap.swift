import Foundation

/// Sound class a physical key belongs to. Packs map these to sample files.
enum KeyClass: String {
    case space, enter, backspace
    case row0, row1, row2, row3, row4
    case `default`
}

/// Maps macOS virtual keycodes to a sound class and an approximate horizontal
/// position (0 = left edge, 1 = right edge) used for spatial panning.
enum KeyMap {
    struct KeyInfo {
        let keyClass: KeyClass
        let x: Float
    }

    // ANSI rows, left to right. Position is derived from index within the row.
    // The F-row shares row0's sound but is positioned separately (see below).
    private static let rows: [KeyClass: [UInt16]] = [
        .row0: [53, 50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24],
        .row1: [48, 12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42],
        .row2: [57, 0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39],
        .row3: [56, 6, 7, 8, 9, 11, 45, 46, 43, 47, 44, 60],
        // Bottom row: fn, ctrl, opt, cmd, cmd(r), opt(r), ctrl(r), arrows
        .row4: [63, 59, 58, 55, 54, 61, 62, 123, 125, 126, 124],
    ]

    /// Keycodes for modifier keys (used by the "mute modifier keys" setting).
    static let modifierKeycodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// Keycodes for function keys F1–F20.
    static let functionKeycodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100,
                                               101, 109, 103, 111, 105, 107, 113, 106,
                                               64, 79, 80, 90]

    static let returnKeycodes: Set<UInt16> = [36, 76]

    private static let table: [UInt16: KeyInfo] = {
        var t: [UInt16: KeyInfo] = [:]
        for (cls, codes) in rows {
            for (i, code) in codes.enumerated() {
                t[code] = KeyInfo(keyClass: cls, x: Float(i) / Float(max(codes.count - 1, 1)))
            }
        }
        // F1–F12: row0 sound, own left-to-right positions above the numbers.
        let fRow: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, code) in fRow.enumerated() {
            t[code] = KeyInfo(keyClass: .row0, x: Float(i) / Float(fRow.count - 1))
        }
        t[49] = KeyInfo(keyClass: .space, x: 0.5)          // space
        t[36] = KeyInfo(keyClass: .enter, x: 0.95)         // return
        t[76] = KeyInfo(keyClass: .enter, x: 1.0)          // keypad enter
        t[51] = KeyInfo(keyClass: .backspace, x: 0.95)     // delete
        t[117] = KeyInfo(keyClass: .backspace, x: 1.0)     // forward delete
        // Navigation cluster
        for code: UInt16 in [114, 115, 116, 119, 121] {
            t[code] = KeyInfo(keyClass: .row1, x: 1.0)
        }
        // Numpad
        for code: UInt16 in [65, 67, 69, 71, 75, 78, 81, 82, 83, 84, 85,
                             86, 87, 88, 89, 91, 92] {
            t[code] = KeyInfo(keyClass: .row2, x: 1.0)
        }
        return t
    }()

    static func info(for keycode: UInt16) -> KeyInfo {
        table[keycode] ?? KeyInfo(keyClass: .default, x: 0.5)
    }
}

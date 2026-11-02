import Foundation

struct FrontApp: Equatable {
    let id: String
    let name: String
}

/// The reasons sounds can be muted without the user turning them off.
enum AutomaticMute: Equatable {
    case call
    case screenLocked
    case speakers
    case app(String)
    case idle

    var message: String {
        switch self {
        case .call: "Muted while another app uses the microphone."
        case .screenLocked: "Muted while the screen is locked."
        case .speakers: "Muted on speakers. Plays through headphones only."
        case .app(let name): "Muted in \(name)."
        case .idle: "Muted after inactivity. Press any key to wake it."
        }
    }

    var symbol: String {
        switch self {
        case .call: "mic.fill"
        case .screenLocked: "lock.fill"
        case .speakers: "headphones"
        case .app: "speaker.slash.fill"
        case .idle: "moon.zzz.fill"
        }
    }
}

/// The one status line shown in the menu bar panel and the settings
/// sidebar, so both always agree on what's happening and why.
enum PlaybackStatus: Equatable {
    case needsAccess
    case off(shortcut: String)
    case blocked(app: String)
    case muted(AutomaticMute)
    case playing(pack: String)

    static func from(trusted: Bool, enabled: Bool, shortcut: String, secureInputApp: String?,
                     mute: AutomaticMute?, pack: String) -> PlaybackStatus {
        if !trusted { return .needsAccess }
        if !enabled { return .off(shortcut: shortcut) }
        if let app = secureInputApp { return .blocked(app: app) }
        if let mute { return .muted(mute) }
        return .playing(pack: pack)
    }

    var title: String {
        switch self {
        case .needsAccess: "Needs Accessibility access"
        case .off: "Off"
        case .blocked(let app): "Paused by \(app)"
        case .muted(.call): "Muted during a call"
        case .muted(.screenLocked): "Muted while locked"
        case .muted(.speakers): "Muted on speakers"
        case .muted(.app(let name)): "Muted in \(name)"
        case .muted(.idle): "Muted after inactivity"
        case .playing(let pack): "Playing \(pack)"
        }
    }

    /// One sentence of explanation, when the title alone isn't enough.
    var detail: String? {
        switch self {
        case .needsAccess:
            "Allow ThockBox in System Settings so it can hear key presses. Nothing you type leaves your Mac."
        case .off(let shortcut):
            "Turn it on here or with \(shortcut)."
        case .blocked(let app):
            "\(app) has secure input on, which hides key presses from other apps. That's normal in a password field. If it lasts, quit and reopen \(app)."
        case .muted(.idle):
            "Press any key to wake it."
        case .muted(.speakers):
            "Headphones only is on. Connect headphones to hear keys."
        case .muted, .playing:
            nil
        }
    }

    var symbol: String {
        switch self {
        case .needsAccess: "exclamationmark.triangle.fill"
        case .off: "speaker.slash.fill"
        case .blocked: "lock.shield.fill"
        case .muted(let reason): reason.symbol
        case .playing: "speaker.wave.2.fill"
        }
    }

    /// Something the user has to act on, not a choice they made.
    /// Whether key presses make a sound right now; the menu bar icon shows
    /// "off" otherwise, including while access is missing or input is blocked.
    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    var needsAttention: Bool {
        switch self {
        case .needsAccess, .blocked: true
        default: false
        }
    }
}

import Foundation

struct FrontApp: Equatable {
    let id: String
    let name: String
    var isGame = false

    /// Games say so in their Info.plist (the App Store's Games category or
    /// one of its subcategories). Steam games often leave it out, so a game
    /// installed by Steam counts too.
    static func isGame(category: String?, path: String?) -> Bool {
        if let category, category.hasPrefix("public.app-category."),
           category == "public.app-category.games" || category.hasSuffix("-games") {
            return true
        }
        return path?.contains("/steamapps/common/") ?? false
    }
}

/// The reasons sounds can be muted without the user turning them off.
enum AutomaticMute: Equatable {
    case call
    case meeting
    case screenLocked
    /// The app's name when exactly one app is playing.
    case media(String?)
    case screenShared
    case speakers
    case app(String)
    case game(String)
    case quietHours
    case idle

    var message: String {
        switch self {
        case .call: "Muted while another app uses the microphone."
        case .meeting: "Muted during a calendar event."
        case .screenLocked: "Muted while the screen is locked."
        case .media(let app?): "Muted while \(app) plays sound."
        case .media: "Muted while another app plays sound."
        case .screenShared: "Muted while your screen is shared or recorded."
        case .speakers: "Muted on speakers. Plays through headphones only."
        case .app(let name): "Muted in \(name)."
        case .game(let name): "Muted while playing \(name)."
        case .quietHours: "Muted during quiet hours."
        case .idle: "Muted after inactivity. Press any key to wake it."
        }
    }

    var symbol: String {
        switch self {
        case .call: "mic.fill"
        case .meeting: "calendar"
        case .screenLocked: "lock.fill"
        case .media: "music.note"
        case .screenShared: "rectangle.inset.filled.and.person.filled"
        case .speakers: "headphones"
        case .app: "speaker.slash.fill"
        case .game: "gamecontroller.fill"
        case .quietHours: "moon.fill"
        case .idle: "moon.zzz.fill"
        }
    }
}

/// The one status line shown in the menu bar panel and the settings
/// sidebar, so both always agree on what's happening and why.
enum PlaybackStatus: Equatable {
    case needsAccess
    /// `until` is when sounds come back by themselves, if they will.
    case off(shortcut: String, until: Date? = nil)
    case blocked(app: String)
    case muted(AutomaticMute)
    case playing(pack: String)

    static func from(trusted: Bool, enabled: Bool, offUntil: Date? = nil, shortcut: String,
                     secureInputApp: String?, mute: AutomaticMute?, pack: String) -> PlaybackStatus {
        if !trusted { return .needsAccess }
        if !enabled { return .off(shortcut: shortcut, until: offUntil) }
        if let app = secureInputApp { return .blocked(app: app) }
        if let mute { return .muted(mute) }
        return .playing(pack: pack)
    }

    var title: String {
        switch self {
        case .needsAccess: "Needs Accessibility access"
        case .off(_, let until?): "Off until \(until.formatted(date: .omitted, time: .shortened))"
        case .off: "Off"
        case .blocked(let app): "Paused by \(app)"
        case .muted(.call): "Muted during a call"
        case .muted(.meeting): "Muted during a meeting"
        case .muted(.screenLocked): "Muted while locked"
        case .muted(.media(let app?)): "Muted while \(app) plays"
        case .muted(.media): "Muted while media plays"
        case .muted(.screenShared): "Muted while sharing"
        case .muted(.speakers): "Muted on speakers"
        case .muted(.app(let name)): "Muted in \(name)"
        case .muted(.game(let name)): "Muted while playing \(name)"
        case .muted(.idle): "Muted after inactivity"
        case .muted(.quietHours): "Muted for quiet hours"
        case .playing(let pack): "Playing \(pack)"
        }
    }

    /// One sentence of explanation, when the title alone isn't enough.
    var detail: String? {
        switch self {
        case .needsAccess:
            "Allow ThockBox in System Settings so it can hear key presses. Nothing you type leaves your Mac."
        case .off(let shortcut, _):
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

import AppKit
import Carbon.HIToolbox

/// Which app, if any, has Secure Input on. AppState checks this when the
/// menu or Settings opens.
enum SecureInput {
    /// The app holding Secure Input, if any. While it's on (a focused
    /// password field, Terminal's Secure Keyboard Entry, or an app that
    /// forgot to turn it off), macOS sends no key events to other apps, so
    /// sounds stop with no other sign.
    static func holder() -> String? {
        guard IsSecureEventInputEnabled() else { return nil }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let app = (session?["kCGSSessionSecureInputPID"] as? Int)
            .flatMap { NSRunningApplication(processIdentifier: pid_t($0)) }
        return holderName(bundleID: app?.bundleIdentifier, name: app?.localizedName)
    }

    /// The lock screen always holds Secure Input; that's covered by the
    /// screen-lock mute, so it isn't reported.
    static func holderName(bundleID: String?, name: String?) -> String? {
        guard bundleID != "com.apple.loginwindow" else { return nil }
        return name ?? "Another app"
    }
}

import AppKit
import Foundation

/// Saves ThockBox's settings to a file and reads them back, to bring a
/// setup to another Mac. Only preferences travel: not keystroke counts,
/// not things tied to this Mac (output devices, calendars, login item), and
/// not on/off or a timed off in progress.
enum SettingsTransfer {
    static let keys: Set<String> = [
        "pack", "appPacks", "newSetEachDay", "volume", "toneX", "toneY", "pitchVariation", "spatialAudio",
        "followHeadMovement", "toggleShortcut", "nextSetShortcut", "volumeUpShortcut", "volumeDownShortcut", "muteModifiers", "functionKeysAudible",
        "mouseClicks", "keyReleaseSounds", "scrollSounds", "returnDing", "hapticFeedback", "muteDuringCalls", "muteDuringMeetings",
        "muteWhileMedia", "ignoredMediaApps", "muteWhileGaming", "muteWhileSharing", "muteWhenLocked",
        "headphonesOnly", "idleTimeoutMinutes", "quietHours", "quietStart", "quietEnd", "mutedApps", "playOnlyInListedApps", "showMenuBarIcon", "dimIconWhenOff",
        "showKeystrokesInMenuBar", "showSpeedInMenuBar", "dockIconStyle", "iconClickAction",
        "notifySetChanges", "checkForUpdates",
    ]

    /// Marks a file as ThockBox settings, so another plist isn't taken for one.
    private static let marker = "ThockBoxSettings"

    static func export(from defaults: UserDefaults) throws -> Data {
        var values: [String: Any] = [marker: 1]
        for key in keys {
            if let value = defaults.object(forKey: key) { values[key] = value }
        }
        return try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    struct NotSettings: LocalizedError {
        var errorDescription: String? { "This file isn't a ThockBox settings file." }
    }

    /// Writes the settings found in `data`; keys it doesn't know are skipped.
    /// Returns how many were applied.
    @discardableResult
    static func importSettings(_ data: Data, into defaults: UserDefaults) throws -> Int {
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              values[marker] != nil else { throw NotSettings() }
        let applied = values.filter { keys.contains($0.key) }
        applied.forEach { defaults.set($0.value, forKey: $0.key) }
        return applied.count
    }

    /// Starts a fresh copy once this one has quit, so every setting is read
    /// anew rather than patched in place.
    static func relaunch() {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open \"$0\"",
                           Bundle.main.bundlePath]
        guard (try? shell.run()) != nil else { return }
        NSApp.terminate(nil)
    }
}

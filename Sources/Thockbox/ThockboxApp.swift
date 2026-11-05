import SwiftUI

@main
struct ThockboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    init() {
        if CommandLine.arguments.contains("--test-audio") {
            AudioSmokeTest.run()
        }
    }

    var body: some Scene {
        // SwiftUI writes isInserted back on every scene update. Passing
        // same-value writes through would publish a change, update the scene
        // again and loop: 94% CPU and over 1 GB of memory within minutes.
        MenuBarExtra(isInserted: Binding(
            get: { state.showMenuBarIcon },
            set: { if $0 != state.showMenuBarIcon { state.showMenuBarIcon = $0 } }
        )) {
            MenuView(state: state)
        } label: {
            MenuBarLabel(state: state, stats: state.stats)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// The menu bar icon, with today's keystrokes beside it if chosen. Only
/// this label watches the counts, so typing doesn't re-lay out the menu.
private struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    let stats: StatsStore

    var body: some View {
        let icon = Image(nsImage: state.status.isPlaying ? MenuBarIcon.on
                         : state.dimIconWhenOff ? MenuBarIcon.offDimmed : MenuBarIcon.off)
        if state.showKeystrokesInMenuBar || state.showSpeedInMenuBar {
            KeystrokeLabel(stats: stats, icon: icon,
                           count: state.showKeystrokesInMenuBar, speed: state.showSpeedInMenuBar)
        } else {
            icon
        }
    }
}

/// Watches the counts only while they're shown, so typing doesn't rebuild
/// the label when the count is off.
private struct KeystrokeLabel: View {
    @ObservedObject var stats: StatsStore
    let icon: Image
    let count: Bool
    let speed: Bool

    var body: some View {
        Label {
            Text(MenuBarText.text(today: count ? stats.shown.today : nil,
                                  wordsPerMinute: speed ? stats.shown.wordsPerMinute : nil))
                .monospacedDigit()
        } icon: {
            icon
        }
        .labelStyle(.titleAndIcon)
    }
}

/// What sits beside the menu bar icon: "1.2K", "62 wpm", or "1.2K · 62 wpm".
enum MenuBarText {
    static func text(today: Int?, wordsPerMinute: Int?) -> String {
        var parts: [String] = []
        if let today { parts.append(today.formatted(.number.notation(.compactName))) }
        if let wordsPerMinute { parts.append("\(wordsPerMinute) wpm") }
        return parts.joined(separator: " · ")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.startUp()
        IconClick.install(state: AppState.shared)
        DockIcon.install(state: AppState.shared)
        Updater.shared.startUp()
        // New installs get the welcome window (Accessibility access, pick a
        // sound) until they finish it; updates that need the grant again
        // open Settings. Otherwise start in the menu bar.
        // After any other update, What's New lists what changed.
        let defaults = UserDefaults.standard
        let isNew = WelcomeWindow.isNeeded()
        let notes = WhatsNew.afterLaunch(usedBefore: !isNew)
        if isNew {
            WelcomeWindow.shared.show(askingForAccess: true)
        } else if defaults.bool(forKey: "showSettingsAfterUpdate") {
            defaults.set(false, forKey: "showSettingsAfterUpdate")
            MainWindow.shared.show()
        } else if let notes {
            WhatsNewWindow.shared.show(notes)
        }
    }

    /// Opening ThockBox again (Finder, Launchpad, Spotlight, Dock) while it's
    /// running brings up the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.shared.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.flushStats()
    }

    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        ["soundsEnabled", "soundPack", "soundVolume", "mouseClicks", "scrollSounds", "returnDing", "muteDuringCalls", "muteDuringMeetings", "muteWhileMedia", "muteWhileGaming", "headphonesOnly",
         "muteWhenLocked", "muteWhileSharing", "muteAfterIdle", "automaticallyMuted", "muteReason", "offUntil", "keystrokesToday",
         "keystrokesTotal"].contains(key)
    }

    @objc var soundsEnabled: Bool {
        get { AppState.shared.enabled }
        set { AppState.shared.enabled = newValue }
    }

    @objc var soundPack: String {
        get { AppState.shared.currentPack?.id ?? AppState.shared.selectedPackID }
        set {
            let state = AppState.shared
            guard let pack = state.packs.first(where: {
                $0.id == newValue || $0.name.caseInsensitiveCompare(newValue) == .orderedSame
            }) else { return }
            state.selectPackFromElsewhere(pack.id)
        }
    }

    @objc var soundVolume: Double {
        get { Double(AppState.shared.volume) }
        set { AppState.shared.volume = Float(min(max(newValue, 0), 1)) }
    }

    @objc var muteAfterIdle: Int {
        get { AppState.shared.idleTimeoutMinutes }
        set { AppState.shared.idleTimeoutMinutes = AppState.nearestIdleTimeout(newValue) }
    }

    @objc var mouseClicks: Bool {
        get { AppState.shared.mouseClicks }
        set { AppState.shared.mouseClicks = newValue }
    }

    @objc var scrollSounds: Bool {
        get { AppState.shared.scrollSounds }
        set { AppState.shared.scrollSounds = newValue }
    }

    @objc var returnDing: Bool {
        get { AppState.shared.returnDing }
        set { AppState.shared.returnDing = newValue }
    }

    @objc var muteDuringCalls: Bool {
        get { AppState.shared.muteDuringCalls }
        set { AppState.shared.muteDuringCalls = newValue }
    }

    @objc var muteWhileGaming: Bool {
        get { AppState.shared.muteWhileGaming }
        set { AppState.shared.muteWhileGaming = newValue }
    }

    @objc var muteWhileMedia: Bool {
        get { AppState.shared.muteWhileMedia }
        set { AppState.shared.muteWhileMedia = newValue }
    }

    @objc var muteDuringMeetings: Bool {
        get { AppState.shared.muteDuringMeetings }
        set { AppState.shared.muteDuringMeetings = newValue }
    }

    @objc var headphonesOnly: Bool {
        get { AppState.shared.headphonesOnly }
        set { AppState.shared.headphonesOnly = newValue }
    }

    @objc var muteWhileSharing: Bool {
        get { AppState.shared.muteWhileSharing }
        set { AppState.shared.muteWhileSharing = newValue }
    }

    @objc var muteWhenLocked: Bool {
        get { AppState.shared.muteWhenLocked }
        set { AppState.shared.muteWhenLocked = newValue }
    }

    @objc var automaticallyMuted: Bool { AppState.shared.isAutomaticallyMuted }

    /// Setting a future date turns sounds off until then, like Turn Off For;
    /// missing value (or a time that has passed) turns them on.
    @objc var offUntil: Date? {
        get { AppState.shared.offUntil }
        set {
            if let newValue, newValue > Date() {
                AppState.shared.turnOff(for: newValue.timeIntervalSinceNow)
            } else {
                AppState.shared.enabled = true
            }
        }
    }

    @objc var muteReason: String { AppState.shared.automaticMute?.message ?? "" }

    @objc var keystrokesToday: Int { AppState.shared.stats.shown.today }

    @objc var keystrokesTotal: Int { AppState.shared.stats.shown.total }
}

/// Headless verification used by `make test`: loads every pack, checks all
/// samples decode, and audibly plays a short demo of each set.
enum AudioSmokeTest {
    static func run() -> Never {
        let dir = AppState.soundsDirectory()
        let packs = SoundPack.discover(in: dir)
        guard !packs.isEmpty else {
            print("FAIL: no sound packs found in \(dir.path)")
            exit(1)
        }
        let engine = SoundEngine()
        engine.volume = 0.6
        do { try engine.start() } catch {
            print("FAIL: audio engine did not start: \(error)")
            exit(1)
        }
        var failures = 0
        for pack in packs {
            engine.load(pack: pack)
            var played = 0, missing = 0
            for cls in [KeyClass.row1, .row2, .row3, .space, .enter, .backspace] {
                if engine.playKey(keyClass: cls, up: false, x: Float.random(in: 0...1)) {
                    played += 1
                } else {
                    missing += 1
                }
                Thread.sleep(forTimeInterval: 0.09)
                _ = engine.playKey(keyClass: cls, up: true, x: 0.5)
                Thread.sleep(forTimeInterval: 0.05)
            }
            let hasUp = !pack.samples(for: .default, up: true).isEmpty
            print("pack \(pack.id): \(played) classes played, \(missing) missing, keyup=\(hasUp ? "yes" : "no")")
            if played == 0 { failures += 1 }
        }
        engine.loadExtras(from: dir.appendingPathComponent("_extras"))
        engine.playExtra(named: "ding")
        Thread.sleep(forTimeInterval: 0.8)
        print(failures == 0 ? "OK: \(packs.count) packs verified" : "FAIL: \(failures) packs unplayable")
        exit(failures == 0 ? 0 : 1)
    }
}

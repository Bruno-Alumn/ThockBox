import AppKit
import XCTest
@testable import Thockbox

final class AppStateTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "ThockboxTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func keyDown(_ state: AppState, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
        state.handle(.keyDown(keycode: code, isRepeat: false, flags: flags))
    }

    /// Key presses counted today, read back through the stats store.
    private func counted(_ state: AppState) -> Int {
        state.stats.flush()
        return defaults.integer(forKey: "statsToday")
    }

    func testFirstLaunchDefaults() {
        let state = AppState(defaults: defaults)
        XCTAssertTrue(state.enabled)
        XCTAssertEqual(state.volume, 0.55)
        XCTAssertEqual(state.selectedPackID, "cream")
        XCTAssertEqual(state.idleTimeoutMinutes, 0)
        XCTAssertFalse(state.mouseClicks)
    }

    func testScrollSoundsListenOnlyWhenOn() {
        let state = AppState(defaults: defaults)
        XCTAssertFalse(state.scrollSounds, "off by default")
        XCTAssertFalse(state.listener.listensToScroll)
        state.scrollSounds = true
        XCTAssertTrue(state.listener.listensToScroll)
        XCTAssertTrue(AppState(defaults: defaults).scrollSounds, "saved")
    }

    func testSetChangesFromElsewhereNotifyOnlyWhenAsked() {
        let state = AppState(defaults: defaults)
        state.postsNotifications = false
        let other = "holy-panda"
        XCTAssertFalse(state.notifySetChanges, "off by default")
        XCTAssertFalse(state.selectPackFromElsewhere(other))
        XCTAssertEqual(state.selectedPackID, other)

        state.notifySetChanges = true
        XCTAssertFalse(state.selectPackFromElsewhere(other), "no change, no notification")
        XCTAssertTrue(state.selectPackFromElsewhere("cream"))
    }

    /// An app with its own set plays it while in front; others play the
    /// selected set, and the choice is saved.
    func testAppSetsFollowTheFrontApp() {
        let state = AppState(defaults: defaults)
        state.reloadPacks()
        let sets = state.packs.map(\.id)
        guard sets.count >= 2 else { return XCTFail("needs two bundled sets, found \(sets)") }
        state.selectedPackID = sets[0]
        state.appPacks = ["com.apple.Terminal": sets[1]]
        state.setFrontApp(id: "com.apple.Terminal", name: "Terminal")
        XCTAssertEqual(state.playingPack?.id, sets[1])
        state.setFrontApp(id: "com.apple.TextEdit", name: "TextEdit")
        XCTAssertEqual(state.playingPack?.id, sets[0])
        XCTAssertEqual(AppState(defaults: defaults).appPacks, ["com.apple.Terminal": sets[1]])
    }

    /// A set that's gone (removed in Finder) falls back to the selected one.
    func testAMissingAppSetFallsBack() {
        let state = AppState(defaults: defaults)
        state.reloadPacks()
        state.appPacks = ["com.apple.Terminal": "no-such-set"]
        state.setFrontApp(id: "com.apple.Terminal", name: "Terminal")
        XCTAssertEqual(state.playingPack?.id, state.currentPack?.id)
    }

    /// The next-set shortcut steps through the sets in order and wraps.
    func testNextSetWrapsAround() {
        let state = AppState(defaults: defaults)
        state.postsNotifications = false
        state.reloadPacks()
        let sets = state.packs.map(\.id)
        state.selectedPackID = sets[sets.count - 2]
        state.switchToNextSet()
        XCTAssertEqual(state.selectedPackID, sets.last)
        state.switchToNextSet()
        XCTAssertEqual(state.selectedPackID, sets.first, "wraps to the first")
    }

    /// With a set each day, the first check on a new day moves to the next
    /// set; more checks that day, or the option off, change nothing.
    func testANewSetEachDay() {
        let state = AppState(defaults: defaults)
        state.postsNotifications = false
        state.reloadPacks()
        let sets = state.packs.map(\.id)
        state.selectedPackID = sets[0]
        // Noon, so an hour later is still the same day whenever this runs.
        let today = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        state.rotateSetIfNewDay(now: today.addingTimeInterval(86_400))
        XCTAssertEqual(state.selectedPackID, sets[0], "off by default")

        state.newSetEachDay = true
        state.rotateSetIfNewDay(now: today)
        XCTAssertEqual(state.selectedPackID, sets[0], "turning it on keeps today's set")
        state.rotateSetIfNewDay(now: today.addingTimeInterval(86_400))
        XCTAssertEqual(state.selectedPackID, sets[1], "next day, next set")
        state.rotateSetIfNewDay(now: today.addingTimeInterval(86_400 + 3600))
        XCTAssertEqual(state.selectedPackID, sets[1], "once a day")
    }

    /// Volume steps by 10%, lands on round values, and never goes silent.
    func testVolumeSteps() {
        let state = AppState(defaults: defaults)
        state.volume = 0.55
        state.stepVolume(by: 0.1)
        XCTAssertEqual(state.volume, 0.65, accuracy: 0.001)
        state.volume = 0.98
        state.stepVolume(by: 0.1)
        XCTAssertEqual(state.volume, 1)
        state.volume = 0.1
        state.stepVolume(by: -0.1)
        XCTAssertEqual(state.volume, 0.05, accuracy: 0.001, "a step down never mutes")
    }

    func testVolumeShortcutsAreSaved() {
        let state = AppState(defaults: defaults)
        XCTAssertNil(state.volumeUpShortcut)
        let up = Shortcut(keyCode: 126, flags: [.control, .command], key: "↑")
        state.volumeUpShortcut = up
        XCTAssertEqual(AppState(defaults: defaults).volumeUpShortcut, up)
        XCTAssertTrue(state.allShortcuts.contains(up))
    }

    func testNextSetShortcutIsSavedAndOffByDefault() {
        let state = AppState(defaults: defaults)
        XCTAssertNil(state.nextSetShortcut)
        let shortcut = Shortcut(keyCode: 45, flags: [.control, .command], key: "N")
        state.nextSetShortcut = shortcut
        XCTAssertEqual(AppState(defaults: defaults).nextSetShortcut, shortcut)
        state.nextSetShortcut = nil
        XCTAssertNil(AppState(defaults: defaults).nextSetShortcut)
    }

    func testUntilMorningIsTheNextEightAM() {
        let calendar = Calendar(identifier: .gregorian)
        let evening = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 23))!
        XCTAssertEqual(AppState.untilMorning(from: evening, calendar: calendar), 9 * 3600)
        let earlyHours = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 2))!
        XCTAssertEqual(AppState.untilMorning(from: earlyHours, calendar: calendar), 6 * 3600, "the same morning")
    }

    func testKeyReleaseSoundsAreOnByDefaultAndSaved() {
        XCTAssertTrue(AppState(defaults: defaults).keyReleaseSounds)
        AppState(defaults: defaults).keyReleaseSounds = false
        XCTAssertFalse(AppState(defaults: defaults).keyReleaseSounds)
    }

    func testKeysTypedByOtherAppsPlayByDefaultAndTheChoiceReachesTheListener() {
        let state = AppState(defaults: defaults)
        XCTAssertTrue(state.generatedKeySounds)
        XCTAssertFalse(state.listener.ignoresGeneratedKeys)
        state.generatedKeySounds = false
        XCTAssertTrue(state.listener.ignoresGeneratedKeys)
        XCTAssertFalse(AppState(defaults: defaults).generatedKeySounds, "saved")
    }

    func testStoredValuesAreClampedOnLoad() {
        defaults.set(5.0, forKey: "volume")
        defaults.set(-9.0, forKey: "toneX")
        defaults.set(999.0, forKey: "pitchVariation")
        defaults.set(-3, forKey: "idleTimeoutMinutes")
        let state = AppState(defaults: defaults)
        XCTAssertEqual(state.volume, 1)
        XCTAssertEqual(state.toneX, -1)
        XCTAssertEqual(state.pitchVariation, 150)
        XCTAssertEqual(state.idleTimeoutMinutes, 0)
    }

    func testSettingsSurviveARelaunch() {
        let state = AppState(defaults: defaults)
        state.muteModifiers = true
        state.functionKeysAudible = false
        let relaunched = AppState(defaults: defaults)
        XCTAssertTrue(relaunched.muteModifiers)
        XCTAssertFalse(relaunched.functionKeysAudible)
    }

    func testHotkeyTogglesSoundsWithoutCountingAKeystroke() {
        let state = AppState(defaults: defaults)
        keyDown(state, Shortcut.standard.keyCode, [.command, .control])
        XCTAssertFalse(state.enabled)
        state.handle(.keyUp(keycode: Shortcut.standard.keyCode))
        keyDown(state, Shortcut.standard.keyCode, [.command, .control])
        XCTAssertTrue(state.enabled)
        XCTAssertEqual(counted(state), 0)
    }

    /// Turn Off for an Hour comes back by itself, survives a relaunch, and
    /// is cancelled by turning sounds on sooner.
    func testTurnOffForAnHour() {
        let now = Date()
        let state = AppState(defaults: defaults)
        state.turnOff(for: 3600, now: now)
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(state.offUntil, now.addingTimeInterval(3600))
        XCTAssertTrue(state.status.title.hasPrefix("Sounds off until "))

        state.resumeIfDue(now: now.addingTimeInterval(1800))
        XCTAssertFalse(state.enabled, "not yet")
        XCTAssertNotNil(state.offUntil, "still waiting after an early check")
        XCTAssertEqual(AppState(defaults: defaults).offUntil, now.addingTimeInterval(3600), "kept across a relaunch")

        state.resumeIfDue(now: now.addingTimeInterval(3600))
        XCTAssertTrue(state.enabled)
        XCTAssertNil(state.offUntil)

        state.turnOff(for: 3600, now: now)
        state.enabled = true
        XCTAssertNil(state.offUntil, "turning on by hand cancels it")
        XCTAssertNil(AppState(defaults: defaults).offUntil)
    }

    /// Turning sounds on with ⌃⌘K mustn't play releases for K, ⌃ and ⌘
    /// that had no press; the next key press ends that.
    func testShortcutReleasesDontClick() {
        let state = AppState(defaults: defaults)
        state.enabled = false
        keyDown(state, Shortcut.standard.keyCode, [.command, .control])
        XCTAssertTrue(state.enabled)
        XCTAssertTrue(state.suppressedKeyUps.isSuperset(of: [Shortcut.standard.keyCode, 55, 59]))
        state.handle(.keyUp(keycode: 55))
        XCTAssertFalse(state.suppressedKeyUps.contains(55), "used up")
        keyDown(state, 0)
        XCTAssertTrue(state.suppressedKeyUps.isEmpty, "a new press ends it")
    }

    /// A Focus filter turns sounds off or picks a set while the Focus is on,
    /// and the Focus ending (default values) puts back what was there.
    func testFocusFilterAppliesAndRestores() {
        let state = AppState(defaults: defaults)
        state.selectedPackID = "cream"
        state.applyFocusFilter(soundsOn: false, packID: nil)
        XCTAssertFalse(state.enabled)
        state.applyFocusFilter(soundsOn: true, packID: nil)
        XCTAssertTrue(state.enabled, "back on when the Focus ends")

        state.applyFocusFilter(soundsOn: true, packID: "holy-panda")
        XCTAssertEqual(state.selectedPackID, "holy-panda")
        state.applyFocusFilter(soundsOn: false, packID: nil)   // switching Focus
        state.applyFocusFilter(soundsOn: true, packID: nil)
        XCTAssertEqual(state.selectedPackID, "cream", "the set from before any Focus")
        XCTAssertTrue(state.enabled)

        state.enabled = false
        state.applyFocusFilter(soundsOn: true, packID: nil)
        XCTAssertFalse(state.enabled, "no Focus active: nothing to put back")
    }

    /// A relaunch during a Focus that turned sounds off still turns them
    /// back on when the Focus ends.
    func testFocusRestoreSurvivesARelaunch() {
        let state = AppState(defaults: defaults)
        state.applyFocusFilter(soundsOn: false, packID: nil)
        XCTAssertFalse(state.enabled)
        let relaunched = AppState(defaults: defaults)
        XCTAssertFalse(relaunched.enabled)
        relaunched.applyFocusFilter(soundsOn: true, packID: nil)
        XCTAssertTrue(relaunched.enabled)
    }

    /// A Focus that only picks a set doesn't turn sounds on, so it neither
    /// undoes turning them off by hand nor cancels a timed off.
    func testSetOnlyFocusLeavesOnOffAlone() {
        let state = AppState(defaults: defaults)
        state.turnOff(for: 3600)
        state.applyFocusFilter(soundsOn: true, packID: "holy-panda")
        XCTAssertFalse(state.enabled)
        XCTAssertNotNil(state.offUntil, "the timed off keeps running")
        state.applyFocusFilter(soundsOn: true, packID: nil)
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(state.selectedPackID, "cream", "the set goes back")
    }

    /// Like Klack, the icon dims while sounds are off unless that's turned off.
    func testIconDimsWhenOffByDefault() {
        XCTAssertTrue(AppState(defaults: defaults).dimIconWhenOff)
        AppState(defaults: defaults).dimIconWhenOff = false
        XCTAssertFalse(AppState(defaults: defaults).dimIconWhenOff, "saved")
    }

    func testCustomShortcutReplacesTheDefaultAndMatchesExactly() {
        let state = AppState(defaults: defaults)
        state.toggleShortcut = Shortcut(keyCode: 49, flags: [.option, .command], key: "Space")
        keyDown(state, Shortcut.standard.keyCode, [.command, .control])
        XCTAssertTrue(state.enabled, "the old shortcut no longer toggles")
        keyDown(state, 49, [.option, .command, .shift])
        XCTAssertTrue(state.enabled, "an extra modifier doesn't match")
        keyDown(state, 49, [.option, .command])
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(AppState(defaults: defaults).toggleShortcut.display, "⌥⌘Space", "saved")
    }

    func testKeystrokesCountOnlyWhileSoundsAreOn() {
        let state = AppState(defaults: defaults)
        keyDown(state, 0)
        keyDown(state, 1)
        XCTAssertEqual(counted(state), 2)
        state.enabled = false
        keyDown(state, 2)
        XCTAssertEqual(counted(state), 2)
    }

    func testMutedModifierKeysAreNotCounted() {
        let state = AppState(defaults: defaults)
        state.muteModifiers = true
        keyDown(state, 56)          // shift
        XCTAssertEqual(counted(state), 0)
        keyDown(state, 0)           // a
        XCTAssertEqual(counted(state), 1)
    }

    func testKeyRepeatIsIgnored() {
        let state = AppState(defaults: defaults)
        state.handle(.keyDown(keycode: 0, isRepeat: true, flags: []))
        XCTAssertEqual(counted(state), 0)
    }
}

final class AutoMuteTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "ThockboxTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testIdleTimeoutMutesAndTypingUnmutes() {
        let state = AppState(defaults: defaults)
        state.idleTimeoutMinutes = 1
        state.updateAutomaticMute(now: Date().addingTimeInterval(30))
        XCTAssertFalse(state.isAutomaticallyMuted, "not idle yet")
        state.updateAutomaticMute(now: Date().addingTimeInterval(61))
        XCTAssertTrue(state.isAutomaticallyMuted)

        state.handle(.keyDown(keycode: 0, isRepeat: false, flags: []))
        XCTAssertFalse(state.isAutomaticallyMuted, "a key press ends idle mute")
    }

    func testIdleMuteIsOffByDefault() {
        let state = AppState(defaults: defaults)
        state.updateAutomaticMute(now: Date().addingTimeInterval(86_400))
        XCTAssertFalse(state.isAutomaticallyMuted)
    }

    func testScreenLockMutesOnlyWhenEnabled() {
        let state = AppState(defaults: defaults)
        state.setScreenLocked(true)
        XCTAssertFalse(state.isAutomaticallyMuted, "mute-when-locked is off")
        state.setScreenLocked(false)

        state.muteWhenLocked = true
        state.setScreenLocked(true)
        XCTAssertTrue(state.isAutomaticallyMuted)
        state.setScreenLocked(false)
        XCTAssertFalse(state.isAutomaticallyMuted)
    }

    func testTurningMuteWhenLockedOnWhileLockedMutesRightAway() {
        let state = AppState(defaults: defaults)
        state.setScreenLocked(true)
        state.muteWhenLocked = true
        XCTAssertTrue(state.isAutomaticallyMuted)
    }

    func testMicrophoneMutesOnlyWhenEnabledAndUntilItStops() {
        let state = AppState(defaults: defaults)
        state.setMicrophoneInUse(true)
        XCTAssertFalse(state.isAutomaticallyMuted, "mute-during-calls is off")

        state.muteDuringCalls = true
        state.setMicrophoneInUse(true)
        XCTAssertTrue(state.isAutomaticallyMuted)
        state.handle(.keyDown(keycode: 0, isRepeat: false, flags: []))
        XCTAssertTrue(state.isAutomaticallyMuted, "typing doesn't end a call mute")
        state.setMicrophoneInUse(false)
        XCTAssertFalse(state.isAutomaticallyMuted)
    }

    /// An app that holds sound open while silent can be ignored; the mute
    /// then only follows the others.
    func testIgnoredMediaAppsDontMute() {
        let state = AppState(defaults: defaults)
        state.muteWhileMedia = true
        state.setPlayingApps(["com.example.callapp"])
        XCTAssertEqual(state.automaticMute, .media("com.example.callapp"), "named (by bundle ID when not installed)")
        state.ignoredMediaApps = ["com.example.callapp"]
        XCTAssertNil(state.automaticMute, "only an ignored app is playing")
        state.setPlayingApps(["com.example.callapp", "com.example.music"])
        XCTAssertEqual(state.automaticMute, .media("com.example.music"), "another app still counts")
        XCTAssertEqual(AppState(defaults: defaults).ignoredMediaApps, ["com.example.callapp"], "saved")
        state.ignoredMediaApps = []
        XCTAssertEqual(state.automaticMute, .media(nil), "two apps: not named")
        XCTAssertEqual(PlaybackStatus.muted(.media("Spotify")).title, "Muted while Spotify plays")
    }

    func testMediaMutesOnlyWhenEnabledAndUntilItStops() {
        let state = AppState(defaults: defaults)
        state.setMediaPlaying(true)
        XCTAssertFalse(state.isAutomaticallyMuted, "mute-while-media is off")

        state.muteWhileMedia = true
        state.setMediaPlaying(true)
        XCTAssertEqual(state.automaticMute, .media("com.example.player"))
        state.setMediaPlaying(false)
        XCTAssertFalse(state.isAutomaticallyMuted)
    }

    func testCalendarEventMutesOnlyWhenEnabled() {
        let state = AppState(defaults: defaults)
        state.readsCalendars = false
        state.setInCalendarEvent(true)
        XCTAssertNil(state.automaticMute, "mute-during-meetings is off")
        state.muteDuringMeetings = true
        state.setInCalendarEvent(true)
        XCTAssertEqual(state.automaticMute, .meeting)
        state.setInCalendarEvent(false)
        XCTAssertNil(state.automaticMute)
    }

    func testQuietHoursSpanMidnight() {
        XCTAssertTrue(AppState.isQuiet(minute: 23 * 60, start: 22 * 60, end: 8 * 60))
        XCTAssertTrue(AppState.isQuiet(minute: 7 * 60 + 59, start: 22 * 60, end: 8 * 60))
        XCTAssertFalse(AppState.isQuiet(minute: 8 * 60, start: 22 * 60, end: 8 * 60), "ends on the minute")
        XCTAssertTrue(AppState.isQuiet(minute: 13 * 60, start: 12 * 60, end: 14 * 60))
        XCTAssertFalse(AppState.isQuiet(minute: 15 * 60, start: 12 * 60, end: 14 * 60))
        XCTAssertFalse(AppState.isQuiet(minute: 9 * 60, start: 9 * 60, end: 9 * 60), "an empty span is never quiet")
    }

    func testQuietHoursMute() {
        let state = AppState(defaults: defaults)
        let night = Calendar.current.startOfDay(for: Date()).addingTimeInterval(23 * 3600)
        state.quietHours = true
        state.updateAutomaticMute(now: night)
        XCTAssertEqual(state.automaticMute, .quietHours)
        state.updateAutomaticMute(now: night.addingTimeInterval(-12 * 3600))
        XCTAssertNil(state.automaticMute, "11am")
        XCTAssertEqual(AppState(defaults: defaults).quietStart, 22 * 60, "default 22:00 to 08:00")
    }

    /// Play Anyway lasts while the same reason does; when it ends and comes
    /// back, the mute does too.
    func testPlayAnywayHoldsUntilTheReasonEnds() {
        let state = AppState(defaults: defaults)
        state.muteWhenLocked = true
        state.setScreenLocked(true)
        XCTAssertEqual(state.automaticMute, .screenLocked)
        state.playAnyway()
        XCTAssertNil(state.automaticMute)
        state.setScreenLocked(true)
        XCTAssertNil(state.automaticMute, "still the same lock")
        state.setScreenLocked(false)
        state.setScreenLocked(true)
        XCTAssertEqual(state.automaticMute, .screenLocked, "a new lock mutes again")
    }

    /// Turned around, the list is where sounds play; everywhere else is quiet.
    func testPlayOnlyInListedApps() {
        let state = AppState(defaults: defaults)
        state.mutedApps = ["com.apple.TextEdit"]
        state.playOnlyInListedApps = true
        state.setFrontApp(id: "com.apple.Safari", name: "Safari")
        XCTAssertEqual(state.automaticMute, .app("Safari"))
        state.setFrontApp(id: "com.apple.TextEdit", name: "TextEdit")
        XCTAssertNil(state.automaticMute)
        XCTAssertTrue(AppState(defaults: defaults).playOnlyInListedApps, "saved")
    }

    /// Playing through one reason doesn't switch off the others: going
    /// idle still mutes.
    func testPlayAnywayLeavesOtherReasonsAlone() {
        let state = AppState(defaults: defaults)
        state.muteWhenLocked = true
        state.idleTimeoutMinutes = 1
        let now = Date()
        state.setScreenLocked(true)
        state.playAnyway()
        XCTAssertNil(state.automaticMute)
        state.updateAutomaticMute(now: now.addingTimeInterval(120))
        XCTAssertEqual(state.automaticMute, .idle, "idle still counts under Play Anyway")
    }

    func testMutedAppMutesOnlyWhileInFront() {
        let state = AppState(defaults: defaults)
        state.setFrontApp(id: "com.example.game", name: "Game")
        XCTAssertNil(state.automaticMute)

        state.mutedApps = ["com.example.game"]
        XCTAssertEqual(state.automaticMute, .app("Game"))
        state.setFrontApp(id: "com.apple.TextEdit", name: "TextEdit")
        XCTAssertNil(state.automaticMute)
        state.setFrontApp(id: "com.example.game", name: "Game")
        state.mutedApps = []
        XCTAssertNil(state.automaticMute, "removing the app unmutes")
    }

    func testMenuBarIconIsShownByDefaultAndRemembered() {
        let state = AppState(defaults: defaults)
        XCTAssertTrue(state.showMenuBarIcon)
        state.showMenuBarIcon = false
        XCTAssertFalse(AppState(defaults: defaults).showMenuBarIcon)
    }

    func testSetMutedNeverAddsAnAppTwice() {
        let state = AppState(defaults: defaults)
        state.setMuted(true, appID: "com.example.game")
        state.setMuted(true, appID: "com.example.game")
        state.setMuted(true, appID: "com.example.editor")
        XCTAssertEqual(state.mutedApps, ["com.example.game", "com.example.editor"])
        state.setMuted(false, appID: "com.example.game")
        XCTAssertEqual(state.mutedApps, ["com.example.editor"])
    }

    func testGameMutesOnlyWhenEnabledAndInFront() {
        let state = AppState(defaults: defaults)
        state.setFrontApp(id: "com.example.game", name: "Game", isGame: true)
        XCTAssertNil(state.automaticMute, "mute-while-gaming is off")
        state.muteWhileGaming = true
        XCTAssertEqual(state.automaticMute, .game("Game"))
        state.setFrontApp(id: "com.apple.TextEdit", name: "TextEdit")
        XCTAssertNil(state.automaticMute)
    }

    func testOnlyRegularAppsCountAsTheFrontApp() {
        XCTAssertTrue(FrontApp.counts(.regular, path: "/Applications/Safari.app"))
        XCTAssertTrue(FrontApp.counts(.regular, path: "/System/Applications/Notes.app"))
        XCTAssertFalse(FrontApp.counts(.accessory, path: "/System/Library/CoreServices/CoreLocationAgent.app"),
                       "a system prompt")
        XCTAssertTrue(FrontApp.counts(.accessory, path: "/Applications/Raycast.app"), "a menu bar app you type into")
    }

    func testGamesAreRecognized() {
        XCTAssertTrue(FrontApp.isGame(category: "public.app-category.games", path: nil))
        XCTAssertTrue(FrontApp.isGame(category: "public.app-category.puzzle-games", path: nil))
        XCTAssertFalse(FrontApp.isGame(category: "public.app-category.productivity", path: nil))
        XCTAssertFalse(FrontApp.isGame(category: nil, path: "/Applications/TextEdit.app"))
        XCTAssertTrue(FrontApp.isGame(category: nil,
            path: "/Users/me/Library/Application Support/Steam/steamapps/common/Portal 2/portal2.app"))
    }

    func testOwnWindowsDontChangeTheFrontApp() {
        let state = AppState(defaults: defaults)
        state.setFrontApp(id: "com.example.game", name: "Game")
        state.setFrontApp(id: Bundle.main.bundleIdentifier, name: "ThockBox")
        XCTAssertEqual(state.frontApp, FrontApp(id: "com.example.game", name: "Game"))
    }

    func testEachOutputDeviceKeepsItsOwnVolume() {
        let state = AppState(defaults: defaults)
        state.setActiveOutput(uid: "speakers")
        state.volume = 0.8
        state.setActiveOutput(uid: "headphones")
        XCTAssertEqual(state.volume, 0.8, "a new device starts at the current volume")
        state.volume = 0.2
        state.setActiveOutput(uid: "speakers")
        XCTAssertEqual(state.volume, 0.8)
        state.setActiveOutput(uid: "headphones")
        XCTAssertEqual(state.volume, 0.2)

        let relaunched = AppState(defaults: defaults)
        relaunched.setActiveOutput(uid: "speakers")
        XCTAssertEqual(relaunched.volume, 0.8, "saved across launches")
    }

    func testAutomaticMuteReportsWhy() {
        let state = AppState(defaults: defaults)
        state.muteWhenLocked = true
        state.muteDuringCalls = true
        state.setScreenLocked(true)
        XCTAssertEqual(state.automaticMute, .screenLocked)
        state.setMicrophoneInUse(true)
        XCTAssertEqual(state.automaticMute, .call, "a call outranks the lock screen")
        state.setMicrophoneInUse(false)
        XCTAssertEqual(state.automaticMute, .screenLocked)
        state.setScreenLocked(false)
        XCTAssertNil(state.automaticMute)
    }

    /// Quiet while the screen is shared or recorded, only with the setting
    /// on, and back once sharing stops.
    func testMutesWhileTheScreenIsShared() {
        let defaults = UserDefaults(suiteName: "AutoMute.sharing.\(UUID().uuidString)")!
        let state = AppState(defaults: defaults)
        state.isScreenCaptured = { false }
        state.setScreenShared(true)
        XCTAssertNil(state.automaticMute, "setting off")
        state.muteWhileSharing = true
        state.setScreenShared(true)
        XCTAssertEqual(state.automaticMute, .screenShared)
        XCTAssertEqual(state.status.title, "Muted while sharing")
        state.setScreenShared(false)
        XCTAssertNil(state.automaticMute)
    }

    /// Capture already going when the setting is turned on (a recording, or
    /// a screenshot tool) mutes right away. This used to depend on whether
    /// the Mac was being captured while the tests ran.
    func testTurningSharingMuteOnDuringACaptureMutes() {
        let defaults = UserDefaults(suiteName: "AutoMute.sharing.\(UUID().uuidString)")!
        let state = AppState(defaults: defaults)
        state.isScreenCaptured = { true }
        state.setScreenShared(true)
        state.muteWhileSharing = true
        XCTAssertEqual(state.automaticMute, .screenShared)
    }
}

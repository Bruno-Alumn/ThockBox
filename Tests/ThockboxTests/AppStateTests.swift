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
        XCTAssertTrue(state.status.title.hasPrefix("Off until "))

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
        state.setPlayingApps(["us.zoom.xos"])
        XCTAssertEqual(state.automaticMute, .media)
        state.ignoredMediaApps = ["us.zoom.xos"]
        XCTAssertNil(state.automaticMute, "only an ignored app is playing")
        state.setPlayingApps(["us.zoom.xos", "com.spotify.client"])
        XCTAssertEqual(state.automaticMute, .media, "another app still counts")
        XCTAssertEqual(AppState(defaults: defaults).ignoredMediaApps, ["us.zoom.xos"], "saved")
    }

    func testMediaMutesOnlyWhenEnabledAndUntilItStops() {
        let state = AppState(defaults: defaults)
        state.setMediaPlaying(true)
        XCTAssertFalse(state.isAutomaticallyMuted, "mute-while-media is off")

        state.muteWhileMedia = true
        state.setMediaPlaying(true)
        XCTAssertEqual(state.automaticMute, .media)
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

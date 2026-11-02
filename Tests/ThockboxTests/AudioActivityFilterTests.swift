import XCTest
@testable import Thockbox

final class AudioActivityFilterTests: XCTestCase {
    private func counts(recording: Bool = true, pid: pid_t = 500, bundleID: String? = "us.zoom.xos") -> Bool {
        AudioActivityMonitor.countsAsCall(recording: recording, pid: pid, ownPID: 100, bundleID: bundleID)
    }

    func testAnotherAppRecordingIsACall() {
        XCTAssertTrue(counts())
        XCTAssertTrue(counts(bundleID: nil), "an app without a bundle ID still counts")
    }

    func testNotRecordingIsNot() {
        XCTAssertFalse(counts(recording: false))
    }

    func testThockBoxItselfIsNot() {
        XCTAssertFalse(counts(pid: 100))
    }

    /// "Hey Siri" and Voice Control listen all the time; counting them would
    /// keep sounds muted for good.
    func testAlwaysListeningServicesAreNot() {
        for id in AudioActivityMonitor.alwaysListening {
            XCTAssertFalse(counts(bundleID: id), id)
        }
        XCTAssertTrue(AudioActivityMonitor.alwaysListening.contains("com.apple.CoreSpeech"), "the one seen on a real Mac")
    }

    func testBundleIDIsOnlyLookedUpWhenNeeded() {
        var lookedUp = false
        func lookup() -> String? { lookedUp = true; return "us.zoom.xos" }
        _ = AudioActivityMonitor.countsAsCall(recording: false, pid: 500, ownPID: 100, bundleID: lookup())
        XCTAssertFalse(lookedUp, "skipped for processes that aren't recording")
    }

    private func media(playing: Bool = true, pid: pid_t = 500, bundleID: String? = "com.spotify.client") -> Bool {
        AudioActivityMonitor.countsAsMedia(playing: playing, pid: pid, ownPID: 100, bundleID: bundleID)
    }

    func testAnotherAppPlayingIsMedia() {
        XCTAssertTrue(media())
        XCTAssertFalse(media(playing: false))
        XCTAssertFalse(media(pid: 100), "ThockBox's own sound")
    }

    /// Alerts and spoken feedback aren't media; VoiceOver in particular
    /// would otherwise mute keys for a screen reader user.
    func testSystemSoundsAreNotMedia() {
        for id in AudioActivityMonitor.systemSounds {
            XCTAssertFalse(media(bundleID: id), id)
        }
        XCTAssertTrue(AudioActivityMonitor.systemSounds.contains("systemsoundserverd"), "the one seen on a real Mac")
    }
}

import XCTest
@testable import Thockbox

final class MicrophoneFilterTests: XCTestCase {
    private func counts(recording: Bool = true, pid: pid_t = 500, bundleID: String? = "us.zoom.xos") -> Bool {
        MicrophoneMonitor.countsAsCall(recording: recording, pid: pid, ownPID: 100, bundleID: bundleID)
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
        for id in MicrophoneMonitor.alwaysListening {
            XCTAssertFalse(counts(bundleID: id), id)
        }
        XCTAssertTrue(MicrophoneMonitor.alwaysListening.contains("com.apple.CoreSpeech"), "the one seen on a real Mac")
    }

    func testBundleIDIsOnlyLookedUpWhenNeeded() {
        var lookedUp = false
        func lookup() -> String? { lookedUp = true; return "us.zoom.xos" }
        _ = MicrophoneMonitor.countsAsCall(recording: false, pid: 500, ownPID: 100, bundleID: lookup())
        XCTAssertFalse(lookedUp, "skipped for processes that aren't recording")
    }
}

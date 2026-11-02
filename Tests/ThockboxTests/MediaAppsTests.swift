import XCTest
@testable import Thockbox

final class MediaAppsTests: XCTestCase {
    private func summary(_ playing: Set<String>, ignoring ignored: Set<String> = []) -> String {
        MediaApps.summary(playing: playing, ignored: ignored) { $0 == "com.spotify.client" ? "Spotify" : $0 }
    }

    func testLabelNamesWhatCounts() {
        XCTAssertEqual(summary([]), "None")
        XCTAssertEqual(summary(["com.spotify.client"]), "Spotify")
        XCTAssertEqual(summary(["com.spotify.client", "us.zoom.xos"]), "2 apps")
        XCTAssertEqual(summary(["com.spotify.client", "us.zoom.xos"], ignoring: ["us.zoom.xos"]), "Spotify")
        XCTAssertEqual(summary(["us.zoom.xos"], ignoring: ["us.zoom.xos"]), "None")
    }

    func testNamesComeFromTheApp() {
        XCTAssertEqual(MediaApps.name("com.apple.Music"), "Music")
        XCTAssertEqual(MediaApps.name("process:afplay"), "afplay")
        XCTAssertEqual(MediaApps.name("process:"), "Other audio")
        XCTAssertEqual(MediaApps.name("com.example.not-installed"), "com.example.not-installed")
    }

    func testProcessesWithoutABundleAreNamed() {
        XCTAssertEqual(AudioActivityMonitor.processKey(getpid()), "process:" + ProcessInfo.processInfo.processName.prefix(15))
    }
}

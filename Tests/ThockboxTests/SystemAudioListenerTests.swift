import CoreAudio
import XCTest
@testable import Thockbox

final class SystemAudioListenerTests: XCTestCase {
    /// A released listener must stop firing. Listener blocks passed from
    /// Swift were never removed, so they piled up with every re-register.
    func testReleasedListenerStopsFiring() throws {
        var kept = 0, released = 0
        let listener = SystemAudioListener(kAudioHardwarePropertyProcessObjectList) { kept += 1 }
        for _ in 0..<3 {
            _ = SystemAudioListener(kAudioHardwarePropertyProcessObjectList) { released += 1 }
        }

        // A new process using audio changes the process list.
        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = ["-v", "0", "/System/Library/Sounds/Tink.aiff"]
        try player.run()
        player.waitUntilExit()

        let deadline = Date().addingTimeInterval(5)
        while kept == 0, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        withExtendedLifetime(listener) {}
        try XCTSkipIf(kept == 0, "CoreAudio reported no process change here")
        XCTAssertEqual(released, 0)
    }

    /// A command-line player has an empty bundle ID; it's listed by its
    /// process name so it can be shown and ignored.
    func testCommandLinePlayerIsListedByName() throws {
        try XCTSkipUnless(AudioActivityMonitor.isSupported)
        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = ["-v", "0.01", "-t", "2", "/System/Library/Sounds/Submarine.aiff"]
        try player.run()
        defer { player.terminate() }
        var apps: Set<String> = []
        let deadline = Date().addingTimeInterval(1.5)
        while !apps.contains(AudioActivityMonitor.processPrefix + "afplay"), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            apps = AudioActivityMonitor.others(.playing)
        }
        try XCTSkipIf(apps.isEmpty, "no audio output here")
        XCTAssertTrue(apps.contains(AudioActivityMonitor.processPrefix + "afplay"), "\(apps)")
        XCTAssertFalse(apps.contains(""))
    }
}

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
}

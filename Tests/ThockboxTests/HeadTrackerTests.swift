import XCTest
@testable import Thockbox

@available(macOS 14, *)
final class HeadTrackerTests: XCTestCase {
    /// Turning the head left (Core Motion's positive yaw) turns the listener
    /// left (AVAudio's negative yaw), so the keys stay in place.
    func testHeadTurnsTheListener() {
        let left = HeadTracker.listenerOrientation(yaw: .pi / 2, pitch: 0)
        XCTAssertEqual(left.yaw, -90, accuracy: 0.001)
        let nod = HeadTracker.listenerOrientation(yaw: 0, pitch: -.pi / 6)
        XCTAssertEqual(nod.pitch, -30, accuracy: 0.001)
        XCTAssertEqual(nod.yaw, 0, accuracy: 0.001)
    }

    func testTheSettingIsSavedAndOffByDefault() {
        let suite = "ThockboxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.tracksHead = false
        XCTAssertFalse(state.followHeadMovement)
        state.followHeadMovement = true
        XCTAssertTrue(AppState(defaults: defaults).followHeadMovement)
    }
}

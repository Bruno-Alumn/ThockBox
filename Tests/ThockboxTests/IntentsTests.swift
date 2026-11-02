import XCTest
@testable import Thockbox

/// The Shortcuts actions change the same state the menu does.
@MainActor
final class IntentsTests: XCTestCase {
    private var saved: (enabled: Bool, volume: Float, pack: String)!

    override func setUp() async throws {
        let state = AppState.shared
        saved = (state.enabled, state.volume, state.selectedPackID)
    }

    override func tearDown() async throws {
        let state = AppState.shared
        state.enabled = saved.enabled
        state.volume = saved.volume
        state.selectedPackID = saved.pack
    }

    func testSetAndToggleSounds() async throws {
        var set = SetSoundsIntent()
        set.on = false
        _ = try await set.perform()
        XCTAssertFalse(AppState.shared.enabled)
        _ = try await ToggleSoundsIntent().perform()
        XCTAssertTrue(AppState.shared.enabled)
    }

    func testTurnOffForAWhile() async throws {
        var intent = TurnOffForIntent()
        intent.minutes = 30
        let before = Date()
        _ = try await intent.perform()
        XCTAssertFalse(AppState.shared.enabled)
        let until = try XCTUnwrap(AppState.shared.offUntil)
        XCTAssertEqual(until.timeIntervalSince(before), 30 * 60, accuracy: 5)
        AppState.shared.enabled = true
        XCTAssertNil(AppState.shared.offUntil)
    }

    func testSetVolumeClampsToRange() async throws {
        var intent = SetVolumeIntent()
        intent.percent = 30
        _ = try await intent.perform()
        XCTAssertEqual(AppState.shared.volume, 0.3, accuracy: 0.001)
        intent.percent = 250
        _ = try await intent.perform()
        XCTAssertEqual(AppState.shared.volume, 1)
    }

    func testSetSwitchSet() async throws {
        var intent = SetSwitchSetIntent()
        intent.switchSet = SwitchSetEntity(id: "holy-panda", name: "Holy Panda")
        _ = try await intent.perform()
        XCTAssertEqual(AppState.shared.selectedPackID, "holy-panda")
    }
}

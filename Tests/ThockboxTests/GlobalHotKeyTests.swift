import Carbon.HIToolbox
import XCTest
@testable import Thockbox

final class GlobalHotKeyTests: XCTestCase {
    func testModifiersMapToCarbon() {
        XCTAssertEqual(GlobalHotKey.carbonModifiers([.control, .command]), UInt32(controlKey | cmdKey))
        XCTAssertEqual(GlobalHotKey.carbonModifiers([.option, .shift]), UInt32(optionKey | shiftKey))
        XCTAssertEqual(GlobalHotKey.carbonModifiers([]), 0)
    }

    /// An unusual combination so it can't clash with the installed app.
    func testRegistersAndReleasesAShortcut() {
        let shortcut = Shortcut(keyCode: 111, flags: [.control, .option, .shift, .command], key: "F12")
        var hotKey = GlobalHotKey(shortcut) {}
        XCTAssertNotNil(hotKey)
        hotKey = nil
        XCTAssertNotNil(GlobalHotKey(shortcut) {}, "free again once released")
    }

    /// A shortcut saved under 1.1.1's looser rule (⌥K) stays with the
    /// listen-only monitor: as a system hotkey it would stop ⌥K typing ˚ in
    /// every app. One that meets the rule becomes a hotkey.
    @MainActor
    func testOnlyShortcutsThatMeetTheRuleBecomeHotKeys() throws {
        let suite = "ThockboxTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = Shortcut(keyCode: 40, flags: [.option], key: "K")
        defaults.set(try JSONEncoder().encode(legacy), forKey: "toggleShortcut")
        let state = AppState(defaults: defaults)
        state.startHotKeys()
        XCTAssertFalse(state.usesSystemHotKey)

        // An unusual combination, so it can't clash with the installed app.
        state.toggleShortcut = Shortcut(keyCode: 111, flags: [.control, .option, .shift, .command], key: "F12")
        XCTAssertTrue(state.usesSystemHotKey)
        state.isRecordingShortcut = true
        XCTAssertFalse(state.usesSystemHotKey, "released while recording")
        state.isRecordingShortcut = false
        XCTAssertTrue(state.usesSystemHotKey)
    }
}

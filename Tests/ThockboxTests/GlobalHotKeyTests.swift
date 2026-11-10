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
        state.recordingShortcut = "Turn sounds on or off"
        XCTAssertFalse(state.usesSystemHotKey, "released while recording")
        state.recordingShortcut = nil
        XCTAssertTrue(state.usesSystemHotKey)
    }

    /// Each hotkey's handler sees every hotkey press; only the one whose ID
    /// matches acts, so the next-set shortcut doesn't also toggle sounds.
    func testOnlyTheMatchingHotKeyActs() throws {
        var fired: [UInt32] = []
        let first = GlobalHotKey(Shortcut(keyCode: 111, flags: [.control, .option, .shift, .command], key: "F12"), id: 1) {
            fired.append(1)
        }
        let second = GlobalHotKey(Shortcut(keyCode: 103, flags: [.control, .option, .shift, .command], key: "F11"), id: 2) {
            fired.append(2)
        }
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        var event: EventRef?
        XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event), noErr)
        // The first one's ID: handlers run newest first, so the second
        // handler sees this press first and must pass it on.
        var id = EventHotKeyID(signature: OSType(0x54686B62), id: 1)
        XCTAssertEqual(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                         MemoryLayout<EventHotKeyID>.size, &id), noErr)
        SendEventToEventTarget(event, GetApplicationEventTarget())
        ReleaseEvent(event)
        XCTAssertEqual(fired, [1])
        _ = (first, second)
    }
}

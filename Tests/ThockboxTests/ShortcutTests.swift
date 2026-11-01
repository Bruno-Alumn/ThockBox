import AppKit
import XCTest
@testable import Thockbox

final class ShortcutTests: XCTestCase {
    private func event(_ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: 0, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    func testRecordsCombinationsWithACommandKey() {
        XCTAssertEqual(Shortcut(event: event(40, "k", [.command, .control]))?.display, "⌃⌘K")
        XCTAssertEqual(Shortcut(event: event(49, " ", [.option, .shift]))?.display, "⌥⇧Space")
        XCTAssertEqual(Shortcut(event: event(40, "k", [.command, .control])), .standard)
    }

    func testRejectsKeysThatWouldFireWhileTyping() {
        XCTAssertNil(Shortcut(event: event(40, "k", [])))
        XCTAssertNil(Shortcut(event: event(40, "K", [.shift])))
    }

    func testIgnoresNonModifierFlags() {
        XCTAssertTrue(Shortcut.standard.matches(keyCode: 40, flags: [.command, .control, .capsLock, .numericPad]))
        XCTAssertFalse(Shortcut.standard.matches(keyCode: 40, flags: [.command, .control, .option]))
    }
}

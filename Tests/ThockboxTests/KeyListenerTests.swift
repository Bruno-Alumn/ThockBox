import XCTest
@testable import Thockbox

final class KeyListenerTests: XCTestCase {
    func testMouseMonitorsOnlyWhileMouseSoundsAreOn() {
        let listener = KeyListener()
        listener.start()
        defer { listener.stop() }
        XCTAssertTrue(listener.mouseMonitors.isEmpty, "off by default")

        listener.listensToMouse = true
        XCTAssertFalse(listener.mouseMonitors.isEmpty)

        listener.listensToMouse = false
        XCTAssertTrue(listener.mouseMonitors.isEmpty)
    }

    func testSettingBeforeStartIsAppliedOnStart() {
        let listener = KeyListener()
        listener.listensToMouse = true
        XCTAssertTrue(listener.mouseMonitors.isEmpty, "nothing installed before start")
        listener.start()
        XCTAssertFalse(listener.mouseMonitors.isEmpty)
        listener.stop()
        XCTAssertTrue(listener.mouseMonitors.isEmpty, "stop removes them")
    }

    func testKeysPostedByAProcessAreGenerated() {
        let posted = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState),
                             virtualKey: 0, keyDown: true)!
        XCTAssertTrue(KeyListener.isGenerated(posted), "carries this test's process ID")
        posted.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        XCTAssertFalse(KeyListener.isGenerated(posted), "no process: from a keyboard")
        XCTAssertFalse(KeyListener.isGenerated(nil))
    }
}

final class ModifierDirectionTests: XCTestCase {
    private let leftShift: UInt16 = 56, rightShift: UInt16 = 60
    private let leftShiftBit: UInt = 0x0002, rightShiftBit: UInt = 0x0004

    private func flags(_ bits: UInt, _ base: NSEvent.ModifierFlags = []) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: base.rawValue | bits)
    }

    private func press(_ code: UInt16, _ f: NSEvent.ModifierFlags, wasDown: Bool = false) -> Bool {
        KeyListener.isModifierPress(code: code, flags: f, wasDown: wasDown)
    }

    func testShiftPressAndRelease() {
        XCTAssertTrue(press(leftShift, flags(leftShiftBit, .shift)))
        XCTAssertFalse(press(leftShift, [], wasDown: true))
    }

    func testReleasingOneShiftWhileTheOtherIsHeld() {
        // Both down, then right released: .shift is still set, but only the
        // left device bit remains, so right must read as a release.
        XCTAssertTrue(press(rightShift, flags(leftShiftBit | rightShiftBit, .shift), wasDown: false))
        XCTAssertFalse(press(rightShift, flags(leftShiftBit, .shift), wasDown: true))
    }

    func testDirectionComesFromFlagsNotFromRememberedState() {
        // A missed event must not invert the state: the flags win.
        XCTAssertTrue(press(leftShift, flags(leftShiftBit, .shift), wasDown: true))
        XCTAssertFalse(press(leftShift, [], wasDown: false))
    }

    func testFunctionKey() {
        XCTAssertTrue(press(63, .function))
        XCTAssertFalse(press(63, [], wasDown: true))
    }

    func testCapsLockAlwaysPresses() {
        XCTAssertTrue(press(57, .capsLock))
        XCTAssertTrue(press(57, [], wasDown: true))
    }

    func testUnknownModifierToggles() {
        XCTAssertTrue(press(999, [], wasDown: false))
        XCTAssertFalse(press(999, [], wasDown: true))
    }
}

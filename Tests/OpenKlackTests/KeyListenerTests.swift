import XCTest
@testable import OpenKlack

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
}

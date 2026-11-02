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
}

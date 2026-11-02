import AppKit
import XCTest
@testable import Thockbox

final class SpokenValueTests: XCTestCase {
    func testPercentages() {
        XCTAssertEqual(SpokenValue.percent(0.55), "55%")
        XCTAssertEqual(SpokenValue.percent(60, of: 150), "40%")
    }

    /// A -1...1 slider says which way and how far, not "50%" at the middle.
    func testDirections() {
        XCTAssertEqual(SpokenValue.direction(0, up: "brighter", down: "darker"), "Neutral")
        XCTAssertEqual(SpokenValue.direction(0.3, up: "brighter", down: "darker"), "30% brighter")
        XCTAssertEqual(SpokenValue.direction(-0.2, up: "higher", down: "lower"), "20% lower")
    }

    func testShortcutsAsWords() {
        XCTAssertEqual(Shortcut.standard.spoken, "Control Command K")
        XCTAssertEqual(Shortcut(keyCode: 49, flags: [.option, .command], key: "Space").spoken, "Option Command Space")
        XCTAssertEqual(Shortcut(keyCode: 123, flags: [.command], key: "←").spoken, "Command Left Arrow")
    }
}

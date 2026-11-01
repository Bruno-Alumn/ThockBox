import XCTest
@testable import Thockbox

final class KeyMapTests: XCTestCase {
    func testSpecialKeys() {
        XCTAssertEqual(KeyMap.info(for: 49).keyClass, .space)
        XCTAssertEqual(KeyMap.info(for: 36).keyClass, .enter)
        XCTAssertEqual(KeyMap.info(for: 76).keyClass, .enter, "keypad enter")
        XCTAssertEqual(KeyMap.info(for: 51).keyClass, .backspace)
    }

    func testRowsAndPositions() {
        let q = KeyMap.info(for: 12), p = KeyMap.info(for: 35)
        XCTAssertEqual(q.keyClass, .row1)
        XCTAssertEqual(p.keyClass, .row1)
        XCTAssertLessThan(q.x, p.x, "Q sits left of P")
        XCTAssertEqual(KeyMap.info(for: 0).keyClass, .row2, "A")
        XCTAssertEqual(KeyMap.info(for: 6).keyClass, .row3, "Z")
    }

    func testUnknownKeyUsesDefaultCentered() {
        let info = KeyMap.info(for: 999)
        XCTAssertEqual(info.keyClass, .default)
        XCTAssertEqual(info.x, 0.5)
    }

    func testEveryPositionIsInRange() {
        for code in UInt16(0)...200 {
            let x = KeyMap.info(for: code).x
            XCTAssertTrue((0...1).contains(x), "keycode \(code) x=\(x)")
        }
    }
}

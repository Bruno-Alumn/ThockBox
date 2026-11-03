import XCTest
@testable import Thockbox

final class MenuBarTextTests: XCTestCase {
    func testTextBesideTheIcon() {
        XCTAssertEqual(MenuBarText.text(today: 1_234, wordsPerMinute: nil), 1_234.formatted(.number.notation(.compactName)))
        XCTAssertEqual(MenuBarText.text(today: nil, wordsPerMinute: 62), "62 wpm")
        XCTAssertEqual(MenuBarText.text(today: 12, wordsPerMinute: 62), "12 · 62 wpm")
        XCTAssertEqual(MenuBarText.text(today: nil, wordsPerMinute: nil), "", "no speed yet: just the icon")
    }
}

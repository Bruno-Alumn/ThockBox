import XCTest
@testable import Thockbox

@MainActor
final class MenuStatsItemTests: XCTestCase {
    func testText() {
        XCTAssertEqual(MenuStatsItem.text(today: 0, wordsPerMinute: nil), "Today: no typing yet")
        XCTAssertEqual(MenuStatsItem.text(today: 1, wordsPerMinute: nil), "Today: 1 key")
        XCTAssertEqual(MenuStatsItem.text(today: 6850, wordsPerMinute: 62), "Today: \(6850.formatted()) keys · 62 wpm")
    }
}

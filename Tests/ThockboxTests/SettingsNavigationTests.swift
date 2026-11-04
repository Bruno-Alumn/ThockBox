import XCTest
@testable import Thockbox

@MainActor
final class SettingsNavigationTests: XCTestCase {
    func testOpensOnTheLastPageUsed() {
        let suite = "ThockboxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(SettingsNavigation(defaults: defaults).page, .sound, "first time: Sound")
        SettingsNavigation(defaults: defaults).page = .activity
        XCTAssertEqual(SettingsNavigation(defaults: defaults).page, .activity)
        defaults.set(99, forKey: SettingsNavigation.lastPageKey)
        XCTAssertEqual(SettingsNavigation(defaults: defaults).page, .sound, "an unknown page falls back")
    }
}

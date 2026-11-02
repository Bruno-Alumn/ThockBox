import XCTest
@testable import Thockbox

final class WelcomeTests: XCTestCase {
    func testOnlyNewInstallsSeeTheWelcome() throws {
        let suite = "ThockboxTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(WelcomeWindow.isNeeded(defaults: defaults), "new install")
        defaults.set(true, forKey: "hasShownSettingsWindow")
        XCTAssertFalse(WelcomeWindow.isNeeded(defaults: defaults), "someone who already used ThockBox")
        defaults.set(false, forKey: "hasShownSettingsWindow")
        defaults.set(true, forKey: "hasFinishedWelcome")
        XCTAssertFalse(WelcomeWindow.isNeeded(defaults: defaults), "finished")
    }
}

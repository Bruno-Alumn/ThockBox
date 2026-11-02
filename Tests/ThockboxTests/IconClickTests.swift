import AppKit
import XCTest
@testable import Thockbox

final class IconClickTests: XCTestCase {
    func testPlainClickTogglesOnlyWhenChosen() {
        XCTAssertFalse(IconClickAction.openMenu.toggles(with: []))
        XCTAssertTrue(IconClickAction.toggleSounds.toggles(with: []))
    }

    /// The menu stays reachable: modifier clicks always open it.
    func testModifierClicksOpenTheMenu() {
        for flags: NSEvent.ModifierFlags in [.control, .option, .command, .shift] {
            XCTAssertFalse(IconClickAction.toggleSounds.toggles(with: flags), "\(flags)")
        }
        XCTAssertTrue(IconClickAction.toggleSounds.toggles(with: [.capsLock]), "Caps Lock doesn't count")
    }

    func testTheChoiceSurvivesARelaunch() {
        let suite = "ThockboxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppState(defaults: defaults).iconClickAction, .openMenu, "the default")
        AppState(defaults: defaults).iconClickAction = .toggleSounds
        XCTAssertEqual(AppState(defaults: defaults).iconClickAction, .toggleSounds)
    }
}

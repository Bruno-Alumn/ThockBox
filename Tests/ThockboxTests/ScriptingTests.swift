import AppKit
import XCTest
@testable import Thockbox

/// Every property in the AppleScript dictionary is one the app delegate
/// claims and actually answers; a key missing from either side fails
/// silently for scripts.
@MainActor
final class ScriptingTests: XCTestCase {
    func testDictionaryKeysAreHandledByTheDelegate() throws {
        let sdef = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Thockbox.sdef")
        let xml = try XMLDocument(contentsOf: sdef)
        let keys = try xml.nodes(forXPath: "//class-extension/property/cocoa/@key").compactMap(\.stringValue)
        XCTAssertGreaterThanOrEqual(keys.count, 11)
        let delegate = AppDelegate()
        for key in keys {
            XCTAssertTrue(delegate.application(NSApplication.shared, delegateHandlesKey: key), "\(key) not claimed")
            XCTAssertTrue(delegate.responds(to: NSSelectorFromString(key)), "\(key) not implemented")
        }
    }

    /// AppleScript can start a timed off by setting `off until`, and end it.
    func testSettingOffUntilTurnsSoundsOffAndOn() {
        let state = AppState.shared
        let wasEnabled = state.enabled
        defer { state.enabled = wasEnabled }
        let delegate = AppDelegate()
        let until = Date().addingTimeInterval(1800)
        delegate.setValue(until, forKey: "offUntil")
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(state.offUntil?.timeIntervalSince1970 ?? 0, until.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual((delegate.value(forKey: "offUntil") as? Date)?.timeIntervalSince1970 ?? 0,
                       until.timeIntervalSince1970, accuracy: 1)
        delegate.setValue(nil, forKey: "offUntil")
        XCTAssertTrue(state.enabled)
        XCTAssertNil(state.offUntil)
    }
}

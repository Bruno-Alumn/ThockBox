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
}

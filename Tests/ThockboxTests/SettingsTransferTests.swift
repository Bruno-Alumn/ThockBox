import XCTest
@testable import Thockbox

final class SettingsTransferTests: XCTestCase {
    private var names: [ObjectIdentifier: String] = [:]

    private func suite() -> (UserDefaults, () -> Void) {
        let name = "ThockboxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        names[ObjectIdentifier(defaults)] = name
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    /// What was actually written, ignoring defaults other tests registered.
    private func stored(_ defaults: UserDefaults, _ key: String) -> Any? {
        defaults.persistentDomain(forName: names[ObjectIdentifier(defaults)]!)?[key]
    }

    func testSettingsTravelButMacSpecificThingsDont() throws {
        let (mac, cleanMac) = suite()
        defer { cleanMac() }
        mac.set("holy-panda", forKey: "pack")
        mac.set(0.3, forKey: "volume")
        mac.set(["com.apple.Terminal": "oreo"], forKey: "appPacks")
        mac.set("BuiltInSpeakerDevice", forKey: "outputDeviceUID")
        mac.set(12_345, forKey: "statsTotal")
        mac.set(false, forKey: "enabled")

        let (other, cleanOther) = suite()
        defer { cleanOther() }
        try SettingsTransfer.importSettings(SettingsTransfer.export(from: mac), into: other)
        XCTAssertEqual(other.string(forKey: "pack"), "holy-panda")
        XCTAssertEqual(other.double(forKey: "volume"), 0.3)
        XCTAssertEqual(other.dictionary(forKey: "appPacks") as? [String: String], ["com.apple.Terminal": "oreo"])
        XCTAssertNil(stored(other, "outputDeviceUID"), "devices belong to this Mac")
        XCTAssertNil(stored(other, "statsTotal"), "counts stay")
        XCTAssertNil(stored(other, "enabled"), "on or off stays")
    }

    func testOtherFilesAreRefused() throws {
        let (defaults, clean) = suite()
        defer { clean() }
        let notOurs = try PropertyListSerialization.data(fromPropertyList: ["pack": "oreo"], format: .xml, options: 0)
        XCTAssertThrowsError(try SettingsTransfer.importSettings(notOurs, into: defaults))
        XCTAssertNil(stored(defaults, "pack"))
        XCTAssertThrowsError(try SettingsTransfer.importSettings(Data("hello".utf8), into: defaults))
    }

    /// A file can't sneak in keys ThockBox doesn't transfer.
    func testUnknownKeysAreSkipped() throws {
        let (defaults, clean) = suite()
        defer { clean() }
        let file = try PropertyListSerialization.data(fromPropertyList: ["ThockBoxSettings": 1, "pack": "oreo",
                                                                         "updateFeedURL": "http://evil.example"],
                                                      format: .xml, options: 0)
        XCTAssertEqual(try SettingsTransfer.importSettings(file, into: defaults), 1)
        XCTAssertNil(stored(defaults, "updateFeedURL"))
    }
}

import XCTest
@testable import Thockbox

/// What the updater accepts from a download before it touches the installed
/// app: exactly one app, ours, of the release's version, correctly signed.
@MainActor
final class UpdateUnpackTests: XCTestCase {
    private var work: URL!
    /// The updater compares against the running app's bundle ID; under XCTest
    /// that's the test runner's.
    private let ownID = Bundle.main.bundleIdentifier ?? "com.apple.dt.xctest.tool"

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("UnpackTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: work)
    }

    /// A minimal app bundle, ad-hoc signed.
    private func makeApp(id: String, version: String, in folder: URL) throws -> URL {
        let app = folder.appendingPathComponent("ThockBox.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: macOS.appendingPathComponent("ThockBox"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macOS.appendingPathComponent("ThockBox").path)
        let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version,
                                   "CFBundleExecutable": "ThockBox", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Updater.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        return app
    }

    private func zip(_ app: URL) throws -> URL {
        let archive = work.appendingPathComponent("update.zip")
        try Updater.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, archive.path])
        return archive
    }

    private func unpack(_ download: URL, expecting version: String = "1.2.0") throws -> URL {
        let into = work.appendingPathComponent("into-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: into, withIntermediateDirectories: true)
        return try Updater.unpack(download, in: into, expecting: version)
    }

    private func assertRefused(_ download: URL, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try unpack(download), file: file, line: line) { error in
            XCTAssertEqual((error as? UpdateError)?.message, message, file: file, line: line)
        }
    }

    private func stage() throws -> URL {
        let folder = work.appendingPathComponent("stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testAcceptsOurSignedAppFromAZip() throws {
        let app = try makeApp(id: ownID, version: "1.2.0", in: try stage())
        XCTAssertEqual(try unpack(zip(app)).lastPathComponent, "ThockBox.app")
    }

    func testAcceptsOurSignedAppFromADiskImage() throws {
        let app = try makeApp(id: ownID, version: "1.2.0", in: try stage())
        let dmg = work.appendingPathComponent("update.dmg")
        try Updater.run("/usr/bin/hdiutil", ["create", "-volname", "ThockBox", "-srcfolder", app.deletingLastPathComponent().path,
                                            "-fs", "HFS+", "-format", "UDZO", "-ov", "-quiet", dmg.path])
        XCTAssertEqual(try unpack(dmg).lastPathComponent, "ThockBox.app")
    }

    /// If hdiutil can't mount it (macOS 27 deprecates `hdiutil attach`),
    /// `diskutil image attach` does, and its output reads the same.
    func testMountsWithDiskutilWhenHdiutilFails() throws {
        try XCTSkipUnless((try? Updater.output("/usr/sbin/diskutil", ["image", "attach", "--help"])) != nil,
                          "diskutil image needs a newer macOS")
        let app = try makeApp(id: ownID, version: "1.2.0", in: try stage())
        let dmg = work.appendingPathComponent("update.dmg")
        try Updater.run("/usr/bin/hdiutil", ["create", "-volname", "ThockBox", "-srcfolder", app.deletingLastPathComponent().path,
                                            "-fs", "HFS+", "-format", "UDZO", "-ov", "-quiet", dmg.path])
        let failing = (tool: "/usr/bin/false", arguments: [String]())
        let mount = try Updater.attach(dmg, using: [failing, Updater.attachCommands[1]])
        defer { try? Updater.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: mount.appendingPathComponent("ThockBox.app").path))
    }

    func testRefusesAnotherVersion() throws {
        let app = try makeApp(id: ownID, version: "1.1.9", in: try stage())
        assertRefused(try zip(app), "The download doesn't match the release.")
    }

    func testRefusesAnotherApp() throws {
        let app = try makeApp(id: "com.example.other", version: "1.2.0", in: try stage())
        assertRefused(try zip(app), "The download doesn't match the release.")
    }

    func testRefusesAnAppChangedAfterSigning() throws {
        let app = try makeApp(id: ownID, version: "1.2.0", in: try stage())
        try "#!/bin/sh\necho changed\n".write(to: app.appendingPathComponent("Contents/MacOS/ThockBox"),
                                             atomically: true, encoding: .utf8)
        assertRefused(try zip(app), "The download's signature is invalid.")
    }

    func testRefusesAnArchiveWithoutTheApp() throws {
        let folder = try stage()
        try "notes".write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        let archive = work.appendingPathComponent("update.zip")
        try Updater.run("/usr/bin/ditto", ["-c", "-k", folder.path, archive.path])
        assertRefused(archive, "The download doesn't contain the app.")
    }
}

import XCTest
@testable import Thockbox

final class UserPacksTests: XCTestCase {
    private var work: URL!
    private var library: URL { work.appendingPathComponent("Library") }
    private static let cream = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Sounds/cream")

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("UserPacksTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: work)
    }

    /// A folder of real recordings, named the way someone might name them.
    private func recordings(_ folder: String, _ names: [String: String]) throws -> URL {
        let dir = work.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, source) in names {
            try FileManager.default.copyItem(at: Self.cream.appendingPathComponent(source),
                                             to: dir.appendingPathComponent(name))
        }
        return dir
    }

    func testFileNamesDecideWhichKeysTheyPlayFor() throws {
        let manifest = try UserPacks.manifest(id: "user-x", name: "X", files: [
            "key1.wav", "key2.wav", "Space Bar.wav", "return.wav", "backspace.wav",
            "key-up.wav", "space_release.wav", "notes.wav",
        ])
        XCTAssertEqual(manifest.keys["default"]?.down, ["key1.wav", "key2.wav", "notes.wav"])
        XCTAssertEqual(manifest.keys["default"]?.up, ["key-up.wav"])
        XCTAssertEqual(manifest.keys["space"]?.down, ["Space Bar.wav"])
        XCTAssertEqual(manifest.keys["space"]?.up, ["space_release.wav"])
        XCTAssertEqual(manifest.keys["enter"]?.down, ["return.wav"])
        XCTAssertEqual(manifest.keys["backspace"]?.down, ["backspace.wav"])
    }

    func testOnlySpecialKeySoundsStillPlayForLetters() throws {
        let manifest = try UserPacks.manifest(id: "user-x", name: "X", files: ["space.wav", "enter.wav"])
        XCTAssertEqual(manifest.keys["default"]?.down, ["enter.wav", "space.wav"])
    }

    func testReleaseOnlyIsRejected() {
        XCTAssertThrowsError(try UserPacks.manifest(id: "user-x", name: "X", files: ["key-up.wav"]))
    }

    func testImportedFolderLoadsAndPlaysLikeABundledSet() throws {
        let folder = try recordings("My Board", [
            "a.mp3": "press/GENERIC_R1.mp3", "b.mp3": "press/GENERIC_R2.mp3",
            "space.mp3": "press/SPACE.mp3", "up.mp3": "release/GENERIC.mp3",
            "readme.txt": "LICENSE",
        ])
        let id = try UserPacks.importPack(from: [folder], into: library)
        XCTAssertEqual(id, "user-my-board")

        let pack = try XCTUnwrap(SoundPack.discover(in: library).first)
        XCTAssertEqual(pack.name, "My Board")
        XCTAssertTrue(UserPacks.isUserPack(pack, in: library))
        XCTAssertEqual(pack.samples(for: .row2, up: false), ["a.mp3", "b.mp3"], "no row sounds: letters use the defaults")
        XCTAssertEqual(pack.samples(for: .space, up: false), ["space.mp3"])
        XCTAssertEqual(pack.samples(for: .row2, up: true), ["up.mp3"])

        let engine = SoundEngine()
        engine.load(pack: pack)
        XCTAssertEqual(engine.buffers.count, 4, "every recording decodes; the text file was skipped")
    }

    func testImportingTwiceKeepsBoth() throws {
        let folder = try recordings("Board", ["a.mp3": "press/GENERIC_R1.mp3"])
        XCTAssertEqual(try UserPacks.importPack(from: [folder], into: library), "user-board")
        XCTAssertEqual(try UserPacks.importPack(from: [folder], into: library), "user-board-2")
        XCTAssertEqual(SoundPack.discover(in: library).count, 2)
    }

    func testFolderWithoutAudioIsRejected() throws {
        let folder = try recordings("Empty", ["readme.txt": "LICENSE"])
        XCTAssertThrowsError(try UserPacks.importPack(from: [folder], into: library))
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.appendingPathComponent("user-empty").path),
                       "nothing is left behind")
    }

    /// A set you added can be exported, shared and added again, keeping its
    /// key mapping (not rebuilt from file names) under an id of its own.
    func testExportedSetImportsAgainUnchanged() throws {
        let folder = try recordings("Desk Board", [
            "a.mp3": "press/GENERIC_R1.mp3", "space.mp3": "press/SPACE.mp3", "up.mp3": "release/GENERIC.mp3",
        ])
        _ = try UserPacks.importPack(from: [folder], into: library)
        let original = try XCTUnwrap(SoundPack.discover(in: library).first)

        let shared = work.appendingPathComponent("Shared")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        let exported = try UserPacks.export(original, to: shared)
        XCTAssertEqual(exported.lastPathComponent, "Desk Board")
        XCTAssertEqual(try UserPacks.export(original, to: shared).lastPathComponent, "Desk Board 2", "never overwrites")

        let id = try UserPacks.importPack(from: [exported], into: library)
        XCTAssertNotEqual(id, original.id, "a copy, not a replacement")
        let copy = try XCTUnwrap(SoundPack.discover(in: library).first { $0.id == id })
        XCTAssertEqual(copy.name, "Desk Board")
        XCTAssertEqual(copy.manifest.keys.mapValues(\.down), original.manifest.keys.mapValues(\.down))
        XCTAssertEqual(copy.samples(for: .space, up: false), ["space.mp3"])
    }

    /// A hand-made or bundled set (a folder with pack.json and subfolders).
    func testImportsABundledStyleSet() throws {
        let id = try UserPacks.importPack(from: [Self.cream.appendingPathComponent("pack.json")], into: library)
        let pack = try XCTUnwrap(SoundPack.discover(in: library).first { $0.id == id })
        XCTAssertEqual(pack.name, "Cream")
        let engine = SoundEngine()
        engine.load(pack: pack)
        XCTAssertFalse(engine.buffers.isEmpty, "files in press/ and release/ came along")
    }
}

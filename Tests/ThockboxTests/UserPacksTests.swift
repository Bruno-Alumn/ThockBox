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

    /// A pack.json whose sounds are missing, outside its folder or not audio
    /// would add a set that plays nothing, so the import says which.
    func testSetWithUnusableSoundsIsRejected() throws {
        let folder = try recordings("Broken", ["a.mp3": "press/GENERIC_R1.mp3"])
        try Data("not audio".utf8).write(to: folder.appendingPathComponent("notes.wav"))
        let outside = try recordings("Elsewhere", ["b.mp3": "press/GENERIC_R1.mp3"])
        func attempt(_ down: [String]) throws -> String {
            let manifest = SoundPackManifest(id: "broken", name: "Broken", attribution: nil, license: nil,
                                             keys: ["default": .init(down: down, up: nil)], gainDb: nil)
            try UserPacks.write(manifest, to: folder)
            return try UserPacks.importPack(from: [folder], into: library)
        }
        for down in [["a.mp3", "gone.mp3"], ["a.mp3", "notes.wav"], ["../\(outside.lastPathComponent)/b.mp3"]] {
            XCTAssertThrowsError(try attempt(down), "\(down)") { error in
                XCTAssertTrue(error.localizedDescription.contains(down.last!), error.localizedDescription)
            }
        }
        XCTAssertEqual(SoundPack.discover(in: library).count, 0, "nothing half-added")
        XCTAssertNoThrow(try attempt(["a.mp3"]))
    }

    /// Files with the same name from different folders all come along.
    func testSameFileNamesFromSeveralFoldersAreKept() throws {
        let one = try recordings("One", ["a.mp3": "press/GENERIC_R1.mp3", "2-a.mp3": "press/GENERIC_R1.mp3"])
        let two = try recordings("Two", ["a.mp3": "press/GENERIC_R1.mp3"])
        let three = try recordings("Three", ["a.mp3": "press/GENERIC_R1.mp3"])
        let files = [one, two, three].flatMap { folder in
            ["a.mp3", "2-a.mp3"].map { folder.appendingPathComponent($0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        let id = try UserPacks.importPack(from: files, into: library)
        let pack = try XCTUnwrap(SoundPack.discover(in: library).first { $0.id == id })
        XCTAssertEqual(pack.samples(for: .default, up: false).count, 4)
    }

    /// A set of yours deleted in Finder disappears the next time the menu or
    /// Settings opens, sound falls back to Cream, and the set comes back
    /// selected if it's restored.
    func testSetDeletedOutsideTheAppIsDropped() throws {
        let bundled = Self.cream.deletingLastPathComponent()
        let suite = "ThockboxTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)

        let folder = try recordings("Gone Soon", ["a.mp3": "press/GENERIC_R1.mp3"])
        let id = try UserPacks.importPack(from: [folder], into: library)
        state.refreshPacks(bundled: bundled, added: library)
        state.selectedPackID = id
        XCTAssertEqual(state.currentPack?.id, id)

        let moved = work.appendingPathComponent("Trash")
        try FileManager.default.moveItem(at: library.appendingPathComponent(id), to: moved)
        state.refreshPacks(bundled: bundled, added: library)
        XCTAssertFalse(state.packs.contains { $0.id == id })
        XCTAssertEqual(state.currentPack?.id, "cream", "falls back to the default set")
        XCTAssertEqual(state.selectedPackID, id, "the choice is kept")

        try FileManager.default.moveItem(at: moved, to: library.appendingPathComponent(id))
        state.refreshPacks(bundled: bundled, added: library)
        XCTAssertEqual(state.currentPack?.id, id, "restored, and selected again")
    }
}

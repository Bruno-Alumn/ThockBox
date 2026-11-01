import XCTest
@testable import OpenKlack

final class SoundPackTests: XCTestCase {
    private func pack(_ keys: [String: SoundPackManifest.KeySounds]) -> SoundPack {
        SoundPack(manifest: SoundPackManifest(id: "t", name: "T", keys: keys),
                  url: URL(fileURLWithPath: "/"))
    }

    func testClassFallsBackToDefaultPerDirection() {
        let p = pack([
            "default": .init(down: ["d.wav"], up: ["u.wav"]),
            "space": .init(down: ["space.wav"], up: nil),
        ])
        XCTAssertEqual(p.samples(for: .space, up: false), ["space.wav"])
        XCTAssertEqual(p.samples(for: .space, up: true), ["u.wav"], "missing up uses default's up")
        XCTAssertEqual(p.samples(for: .enter, up: false), ["d.wav"], "missing class uses default")
    }

    func testDownOnlyPackHasNoReleaseSamples() {
        let p = pack(["default": .init(down: ["d.wav"], up: nil)])
        XCTAssertEqual(p.samples(for: .row2, up: true), [])
    }

    /// Every bundled pack must have a default press sound and only point at
    /// files that exist.
    func testBundledPacksAreComplete() throws {
        let sounds = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Sounds")
        let packs = SoundPack.discover(in: sounds)
        XCTAssertGreaterThanOrEqual(packs.count, 7)
        for p in packs {
            XCTAssertFalse(p.samples(for: .default, up: false).isEmpty, "\(p.id) has no default sound")
            for entry in p.manifest.keys.values {
                for file in entry.down + (entry.up ?? []) {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: p.url.appendingPathComponent(file).path),
                                  "\(p.id): missing \(file)")
                }
            }
        }
    }
}

final class SoundPackDiscoveryTests: XCTestCase {
    func testSkipsBrokenPacksAndKeepsGoodOnes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenKlackTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func pack(_ folder: String, _ json: String?) throws {
            let dir = root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let json { try json.write(to: dir.appendingPathComponent("pack.json"), atomically: true, encoding: .utf8) }
        }
        let good = #"{"id":"good","name":"Good","keys":{"default":{"down":["a.wav"]}}}"#
        try pack("good", good)
        try pack("copy-of-good", good)                                              // duplicate id
        try pack("typo", #"{"id":"typo","name":"Typo","keys":{"default":{"down":["a.wav"]}"#)  // malformed
        try pack("no-default", #"{"id":"nd","name":"No Default","keys":{"space":{"down":["s.wav"]}}}"#)
        try pack("empty-default", #"{"id":"ed","name":"Empty","keys":{"default":{"down":[]}}}"#)
        try pack("_extras", nil)                                                    // not a pack

        let found = SoundPack.discover(in: root)
        XCTAssertEqual(found.map(\.id), ["good"])
    }
}

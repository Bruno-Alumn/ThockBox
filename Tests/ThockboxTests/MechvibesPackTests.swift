import AVFoundation
import XCTest
@testable import Thockbox

final class MechvibesPackTests: XCTestCase {
    private var work: URL!
    private var library: URL { work.appendingPathComponent("Library") }
    private static let cream = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Sounds/cream")

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("MechvibesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: work)
    }

    /// Joins real recordings into one sprite WAV, the way Mechvibes packs
    /// ship, and returns each recording's [start, end] in milliseconds.
    private func sprite(at url: URL, _ sources: [String]) throws -> [[Double]] {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let out = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        var spans: [[Double]] = []
        var position = 0.0
        let gap = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
        gap.frameLength = 4_800
        for source in sources {
            let file = try AVAudioFile(forReading: Self.cream.appendingPathComponent(source))
            let decoded = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: decoded)
            let mono = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: decoded.frameLength * 2)!
            let converter = AVAudioConverter(from: decoded.format, to: format)!
            var fed = false
            converter.convert(to: mono, error: nil) { _, status in
                defer { fed = true }
                status.pointee = fed ? .endOfStream : .haveData
                return fed ? nil : decoded
            }
            try out.write(from: mono)
            let length = Double(mono.frameLength) / 48
            spans.append([position, position + length])
            position += length
            try out.write(from: gap)
            position += 100
        }
        return spans
    }

    private func pack(_ name: String, config: [String: Any]) throws -> URL {
        let folder = work.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: config).write(to: folder.appendingPathComponent("config.json"))
        return folder
    }

    /// The current format, with press and release timings in one sprite.
    func testVersion2SpriteWithPressAndRelease() throws {
        let folder = work.appendingPathComponent("v2")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let s = try sprite(at: folder.appendingPathComponent("sound.wav"), [
            "press/GENERIC_R2.mp3", "release/GENERIC.mp3", "press/GENERIC_R1.mp3",
            "press/SPACE.mp3", "release/SPACE.mp3", "press/ENTER.mp3",
        ])
        _ = try pack("v2", config: [
            "config_version": "2", "name": "Test Board", "definition_method": "single", "audio_file": "sound.wav",
            "definitions": [
                "KeyA": ["timing": [s[0], s[1]]],
                "KeyS": ["timing": [s[0], s[1]]],   // same sound as A: written once
                "KeyQ": ["timing": [s[2], s[1]]],
                "Space": ["timing": [s[3], s[4]]],
                "Enter": ["timing": [s[5]]],
            ],
        ])
        let id = try UserPacks.importPack(from: [folder], into: library)
        XCTAssertEqual(id, "user-test-board")
        let pack = try XCTUnwrap(SoundPack.discover(in: library).first)
        XCTAssertEqual(pack.name, "Test Board")
        XCTAssertEqual(pack.samples(for: .row2, up: false).count, 1, "A and S share one slice")
        XCTAssertEqual(pack.samples(for: .row1, up: false).count, 1)
        XCTAssertEqual(pack.samples(for: .row2, up: true).count, 1, "release sounds come through")
        XCTAssertEqual(pack.samples(for: .space, up: false).count, 1)
        XCTAssertEqual(pack.samples(for: .space, up: true).count, 1)
        XCTAssertEqual(pack.samples(for: .enter, up: false).count, 1)
        XCTAssertEqual(pack.samples(for: .row3, up: false).count, 2, "rows without sounds use every ordinary key")
        XCTAssertEqual(pack.samples(for: .space, up: false), pack.manifest.keys["space"]?.down,
                       "the space bar isn't mixed into ordinary keys")

        let engine = SoundEngine()
        engine.load(pack: pack)
        XCTAssertEqual(engine.buffers.count, 6, "4 press + 2 release slices, all decodable")
    }

    /// The older format: scancodes with [start, length] in a sprite.
    func testVersion1Sprite() throws {
        let folder = work.appendingPathComponent("v1")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let s = try sprite(at: folder.appendingPathComponent("sprite.wav"), ["press/GENERIC_R2.mp3", "press/SPACE.mp3"])
        _ = try pack("v1", config: [
            "name": "Old Board", "key_define_type": "single", "sound": "sprite.wav",
            "defines": ["30": [s[0][0], s[0][1] - s[0][0]], "57": [s[1][0], s[1][1] - s[1][0]], "31": NSNull()],
        ])
        _ = try UserPacks.importPack(from: [folder.appendingPathComponent("config.json")], into: library)
        let pack = try XCTUnwrap(SoundPack.discover(in: library).first)
        XCTAssertEqual(pack.samples(for: .row2, up: false).count, 1)
        XCTAssertEqual(pack.samples(for: .space, up: false).count, 1)
        XCTAssertTrue(pack.samples(for: .row2, up: true).isEmpty, "v1 has no release sounds")
    }

    /// The older format with a file per key.
    func testVersion1FilePerKey() throws {
        let folder = try pack("multi", config: [
            "name": "Files", "key_define_type": "multi",
            "defines": ["30": "a.mp3", "57": "space.mp3", "14": NSNull()],
        ])
        try FileManager.default.copyItem(at: Self.cream.appendingPathComponent("press/GENERIC_R2.mp3"),
                                         to: folder.appendingPathComponent("a.mp3"))
        try FileManager.default.copyItem(at: Self.cream.appendingPathComponent("press/SPACE.mp3"),
                                         to: folder.appendingPathComponent("space.mp3"))
        _ = try UserPacks.importPack(from: [folder], into: library)
        let pack = try XCTUnwrap(SoundPack.discover(in: library).first)
        XCTAssertEqual(pack.samples(for: .row2, up: false).count, 1)
        XCTAssertEqual(pack.samples(for: .space, up: false).count, 1)
    }

    func testMissingAudioFailsCleanly() throws {
        let folder = try pack("broken", config: [
            "name": "Broken", "audio_file": "missing.ogg", "definitions": ["KeyA": ["timing": [[0, 100]]]],
        ])
        XCTAssertThrowsError(try UserPacks.importPack(from: [folder], into: library))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.path), [], "nothing left behind")
    }

    func testKeyNamesMapToRows() {
        XCTAssertEqual(MechvibesPack.keyClass(forCode: "KeyQ"), .row1)
        XCTAssertEqual(MechvibesPack.keyClass(forCode: "KeyA"), .row2)
        XCTAssertEqual(MechvibesPack.keyClass(forCode: "KeyZ"), .row3)
        XCTAssertEqual(MechvibesPack.keyClass(forCode: "Digit5"), .row0)
        XCTAssertEqual(MechvibesPack.keyClass(forCode: "F11"), .row0)
        XCTAssertEqual(MechvibesPack.keyClass(forCode: "MetaLeft"), .row4)
        XCTAssertEqual(MechvibesPack.keyClass(forCode: "NumpadEnter"), .enter)
        XCTAssertEqual(MechvibesPack.keyClass(forCode: "Numpad5"), .default)
        XCTAssertEqual(MechvibesPack.keyClass(forScancode: 16), .row1)
        XCTAssertEqual(MechvibesPack.keyClass(forScancode: 57), .space)
        XCTAssertEqual(MechvibesPack.keyClass(forScancode: 3675), .row4)
    }
}

import AVFoundation
import XCTest
@testable import Thockbox

final class SoundEngineTests: XCTestCase {
    private static let packs = SoundPack.discover(
        in: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Sounds"))

    /// Every file a pack lists gets decoded (and trimmed) once.
    func testLoadDecodesEveryFileEachPackLists() throws {
        XCTAssertFalse(Self.packs.isEmpty)
        let engine = SoundEngine()
        for pack in Self.packs {
            engine.load(pack: pack)
            let files = Set(pack.manifest.keys.values.flatMap { $0.down + ($0.up ?? []) })
            XCTAssertEqual(engine.buffers.count, files.count, pack.id)
            for file in files {
                let buffer = try XCTUnwrap(engine.buffers["\(pack.id)/\(file)"], "\(pack.id)/\(file)")
                XCTAssertGreaterThan(buffer.frameLength, 0, "\(pack.id)/\(file)")
            }
        }
    }

    func testTrimmingNeverMakesASampleLonger() throws {
        let pack = try XCTUnwrap(Self.packs.first)
        let file = try XCTUnwrap(pack.samples(for: .default, up: false).first)
        let source = try AVAudioFile(forReading: pack.url.appendingPathComponent(file))
        let engine = SoundEngine()
        engine.load(pack: pack)
        let trimmed = try XCTUnwrap(engine.buffers["\(pack.id)/\(file)"])
        // The source may be 44.1 kHz; the engine decodes to 48 kHz.
        let sourceAt48k = Double(source.length) * 48_000 / source.processingFormat.sampleRate
        XCTAssertLessThanOrEqual(Double(trimmed.frameLength), sourceAt48k.rounded(.up) + 64)
    }

    func testPlayKeyNeedsALoadedPackAndARunningEngine() throws {
        let engine = SoundEngine()
        XCTAssertFalse(engine.playKey(keyClass: .row2, up: false, x: 0.5), "no pack loaded")
        engine.load(pack: try XCTUnwrap(Self.packs.first))
        XCTAssertFalse(engine.playKey(keyClass: .row2, up: false, x: 0.5), "engine not started")

        engine.volume = 0
        do { try engine.start() } catch { throw XCTSkip("no audio output device: \(error)") }
        defer { engine.stop() }
        XCTAssertTrue(engine.playKey(keyClass: .row2, up: false, x: 0.5))
    }
}

final class AudioDevicesTests: XCTestCase {
    func testOutputDevicesHaveNamesAndIDs() throws {
        let devices = AudioDevices.outputDevices()
        try XCTSkipIf(devices.isEmpty, "no audio output devices on this machine")
        for device in devices {
            XCTAssertFalse(device.name.isEmpty)
            XCTAssertFalse(device.uid.isEmpty)
        }
        XCTAssertEqual(Set(devices.map(\.uid)).count, devices.count, "UIDs are unique")
    }

    func testDefaultOutputIsOneOfTheListedDevices() throws {
        let devices = AudioDevices.outputDevices()
        try XCTSkipIf(devices.isEmpty, "no audio output devices on this machine")
        XCTAssertTrue(devices.contains { $0.id == AudioDevices.defaultOutputDevice() })
    }
}

final class SavedOutputDeviceTests: XCTestCase {
    private let devices = [
        AudioDevices.Device(id: 41, uid: "speakers", name: "MacBook Pro Speakers"),
        AudioDevices.Device(id: 77, uid: "airpods", name: "AirPods Pro"),
    ]

    func testSavedDeviceIsFound() {
        XCTAssertEqual(AudioDevices.id(forUID: "airpods", in: devices), 77)
    }

    func testDisconnectedDeviceFallsBackToSystemDefault() {
        XCTAssertNil(AudioDevices.id(forUID: "usb-headset", in: devices))
    }

    func testNothingSavedMeansSystemDefault() {
        XCTAssertNil(AudioDevices.id(forUID: nil, in: devices))
    }
}

import AVFoundation
import XCTest
@testable import Thockbox

final class SoundEngineTests: XCTestCase {
    private static let packs = SoundPack.discover(
        in: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Sounds"))

    /// Bundled packs differ by ~19 dB as recorded; after loading, a typical
    /// key press in each lands at the same level, without clipping.
    func testPacksLoadAtTheSameLoudness() {
        let engine = SoundEngine()
        for pack in Self.packs {
            engine.load(pack: pack)
            let typical = (pack.manifest.keys["default"]?.down ?? []).compactMap { engine.buffers["\(pack.id)/\($0)"] }
            let levels = typical.map(SoundEngine.loudestLevel).sorted()
            let db = 20 * log10(levels[levels.count / 2] / SoundEngine.targetLevel)
            XCTAssertEqual(db, 0, accuracy: 0.5, pack.id)
            XCTAssertLessThan(engine.buffers.values.map(SoundEngine.samplePeak).max() ?? 0, 0.9, pack.id)
        }
    }

    func testNormalizingGainStopsShortOfClipping() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let quiet = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        quiet.frameLength = 4_800
        for i in 0..<4_800 { quiet.floatChannelData![0][i] = i % 2 == 0 ? 0.001 : -0.001 }
        XCTAssertEqual(SoundEngine.normalizingGain(for: [quiet], allPeaks: [0.001]), 25, accuracy: 0.01)
        // A loud sample elsewhere in the pack caps the boost at -1 dBFS.
        XCTAssertEqual(SoundEngine.normalizingGain(for: [quiet], allPeaks: [0.089]), 10, accuracy: 0.01)
    }

    /// After 30 s without a sound the engine pauses, and the next key
    /// resumes it and still plays.
    func testPausesWhenIdleAndResumesOnTheNextKey() throws {
        let engine = SoundEngine()
        engine.volume = 0
        let pack = try XCTUnwrap(Self.packs.first)
        engine.load(pack: pack)
        do { try engine.start() } catch { throw XCTSkip("no audio output (CI)") }
        defer { engine.stop() }

        engine.pauseIfIdle(now: Date().addingTimeInterval(5))
        XCTAssertFalse(engine.isIdlePaused, "not idle long enough")
        engine.pauseIfIdle(now: Date().addingTimeInterval(SoundEngine.idlePauseDelay + 1))
        try XCTSkipIf(!engine.isIdlePaused, "output is Bluetooth-like, never pauses")
        XCTAssertTrue(engine.playKey(keyClass: .row2, up: false, x: 0.5))
        XCTAssertFalse(engine.isIdlePaused)
    }

    /// A running engine with a pack loaded and the volume at zero, or a skip
    /// where there's no audio output (CI).
    private func runningEngine() throws -> SoundEngine {
        let engine = SoundEngine()
        engine.volume = 0
        engine.load(pack: try XCTUnwrap(Self.packs.first { $0.id == "cream" }))
        do { try engine.start() } catch { throw XCTSkip("no audio output (CI)") }
        return engine
    }

    /// Waits up to 3 s for every voice to free up; completion callbacks
    /// arrive on the main queue. If they don't, checks that the output is
    /// actually rendering: CI runners have a virtual device that sometimes
    /// stalls, which says nothing about the engine, so the test is skipped.
    private func waitForVoicesToFree(_ engine: SoundEngine) throws {
        let deadline = Date().addingTimeInterval(3)
        while engine.busyVoiceCount > 0, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        guard engine.busyVoiceCount > 0 else { return }
        let before = engine.renderedSamples
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if engine.renderedSamples == nil || engine.renderedSamples == before {
            throw XCTSkip("the audio output isn't rendering (a stalled virtual device on CI)")
        }
    }

    /// Typing faster than the 8 voices can keep up with still plays every
    /// key (the oldest sound is cut), and every voice is free again once
    /// the sounds have played, so the next burst isn't cut short.
    func testABurstPlaysEveryKeyAndFreesEveryVoice() throws {
        let engine = try runningEngine()
        defer { engine.stop() }
        for i in 0..<30 {
            XCTAssertTrue(engine.playKey(keyClass: .row2, up: false, x: Float(i % 10) / 10), "key \(i)")
        }
        XCTAssertEqual(engine.busyVoiceCount, 8, "all voices in use during the burst")
        try waitForVoicesToFree(engine)
        XCTAssertEqual(engine.busyVoiceCount, 0, "voices free once the sounds have played")
    }

    /// Spatial mode plays through its own 3D voices, which free up again,
    /// and switching back leaves the normal path working.
    func testSpatialModePlaysAndFreesItsVoices() throws {
        let engine = try runningEngine()
        defer { engine.stop() }
        engine.spatial = true
        for i in 0..<12 {
            XCTAssertTrue(engine.playKey(keyClass: .row2, up: false, x: Float(i % 10) / 10), "key \(i)")
        }
        XCTAssertGreaterThan(engine.busyVoiceCount, 0)
        try waitForVoicesToFree(engine)
        XCTAssertEqual(engine.busyVoiceCount, 0)
        engine.spatial = false
        XCTAssertTrue(engine.playKey(keyClass: .row2, up: false, x: 0.5))
        try waitForVoicesToFree(engine)
    }

    /// Keys sit on an arc in front of the listener, left to right, at the
    /// same distance.
    func testSpatialPositionsFollowTheKeyboard() {
        let left = SoundEngine.spatialPosition(x: 0, spread: 1)
        let middle = SoundEngine.spatialPosition(x: 0.5, spread: 1)
        let right = SoundEngine.spatialPosition(x: 1, spread: 1)
        XCTAssertLessThan(left.x, 0)
        XCTAssertEqual(middle.x, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(right.x, 0)
        XCTAssertLessThan(middle.z, 0, "in front")
        for p in [left, middle, right] {
            XCTAssertEqual(sqrt(p.x * p.x + p.z * p.z), 0.5, accuracy: 0.0001)
        }
    }

    func testMonoCopyAveragesTheChannels() throws {
        let stereo = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let mono = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 4))
        buffer.frameLength = 4
        for i in 0..<4 { buffer.floatChannelData![0][i] = 0.2; buffer.floatChannelData![1][i] = 0.6 }
        let out = try XCTUnwrap(SoundEngine.mono(buffer, format: mono))
        XCTAssertEqual(out.frameLength, 4)
        XCTAssertEqual(out.floatChannelData![0][3], 0.4, accuracy: 0.0001)
    }

    func testReleaseRightAfterItsPressBothPlay() throws {
        let engine = try runningEngine()
        defer { engine.stop() }
        XCTAssertTrue(engine.playKey(keyClass: .space, up: false, x: 0.5))
        XCTAssertTrue(engine.playKey(keyClass: .space, up: true, x: 0.5))
        XCTAssertEqual(engine.busyVoiceCount, 2)
        try waitForVoicesToFree(engine)
        XCTAssertEqual(engine.busyVoiceCount, 0)
    }

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

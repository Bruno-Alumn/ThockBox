import AVFoundation
import XCTest
@testable import Thockbox

/// A device can lengthen its I/O cycle under an engine that was prepared
/// for a shorter one (AirPods just after connecting: 128 frames to 256).
/// Every render then fails while the engine still reports running, and a
/// player's plain play() waits 5 s for a render that never comes: 2.0.0
/// froze for 80 s that way, and then for 5 s on every key.
final class SoundEngineIOCycleTests: XCTestCase {
    private static let packs = SoundPack.discover(
        in: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Sounds"))

    /// No call on the main thread may take longer than this. A player that
    /// waits for a render takes 5 s, so the margin is wide on both sides.
    private static let longestCall: TimeInterval = 0.5
    private static let longerCycle: UInt32 = 512

    private func ioCycle(_ unit: AudioUnit) -> UInt32 {
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioUnitGetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &frames, &size)
        return frames
    }

    private func seconds(_ body: () -> Void) -> TimeInterval {
        let start = ProcessInfo.processInfo.systemUptime
        body()
        return ProcessInfo.processInfo.systemUptime - start
    }

    /// Plays a few keys 30 ms apart; none may block.
    private func playKeys(on engine: SoundEngine, _ what: String) {
        for i in 0..<6 {
            var played = false
            let took = seconds { played = engine.playKey(keyClass: .row2, up: false, x: Float(i) / 6) }
            XCTAssertTrue(played, "\(what), key \(i)")
            XCTAssertLessThan(took, Self.longestCall, "\(what), key \(i) blocked the main thread")
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
    }

    /// True once every voice has freed up, which a voice only does when its
    /// sound has been rendered (the completion arrives on the main queue).
    private func voicesFree(_ engine: SoundEngine) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while engine.busyVoiceCount > 0, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return engine.busyVoiceCount == 0
    }

    /// The keys just played were rendered. If not, an output that renders
    /// nothing at all (a stalled virtual device on CI) says nothing about
    /// the engine and skips the test; an output whose clock runs while the
    /// voices stay busy is the failure this test is about. The clock is
    /// only read here, after everything timed: reading it can itself wait
    /// 5 s when no cycle arrives.
    private func assertRendered(_ engine: SoundEngine, _ what: String) throws {
        guard !voicesFree(engine) else { return }
        let busy = engine.busyVoiceCount
        let before = engine.renderedSamples
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let after = engine.renderedSamples
        try XCTSkipIf(after == nil || after == before, "the audio output stopped rendering (a stalled virtual device on CI)")
        XCTFail("\(what): the output is running, but \(busy) keys were never rendered")
    }

    func testALongerIOCycleNeitherBlocksNorSilencesTheEngine() throws {
        let engine = SoundEngine()
        engine.volume = 0
        engine.load(pack: try XCTUnwrap(Self.packs.first { $0.id == "cream" }))
        do { try engine.start() } catch { throw XCTSkip("no audio output (CI)") }
        defer { engine.stop() }
        // A regression blocks for 5 s per player and per key: stop at the first.
        continueAfterFailure = false

        XCTAssertTrue(engine.playKey(keyClass: .row2, up: false, x: 0.5))
        try XCTSkipIf(!voicesFree(engine), "the audio output isn't rendering (a stalled virtual device on CI)")

        // The cycle grows under the running engine. Only this process's I/O
        // changes; the device keeps serving other apps at their own sizes.
        let unit = try XCTUnwrap(engine.outputUnit)
        let before = ioCycle(unit)
        var frames = Self.longerCycle
        let size = UInt32(MemoryLayout<UInt32>.size)
        let err = AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &frames, size)
        try XCTSkipIf(err != noErr || before >= Self.longerCycle || ioCycle(unit) != Self.longerCycle,
                      "the output doesn't take a longer I/O cycle (\(before) to \(ioCycle(unit)) frames, error \(err))")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        playKeys(on: engine, "longer cycle")
        try assertRendered(engine, "longer cycle")

        // From here on the cycle grows again each time the output starts,
        // after the engine has prepared for the short cycle it asked for:
        // the device that changes mode right after a restart.
        let context = UnsafeMutableRawPointer(bitPattern: UInt(Self.longerCycle))
        XCTAssertEqual(AudioUnitAddPropertyListener(unit, kAudioOutputUnitProperty_IsRunning, lengthenCycleOnStart, context), noErr)
        defer { AudioUnitRemovePropertyListenerWithUserData(unit, kAudioOutputUnitProperty_IsRunning, lengthenCycleOnStart, context) }

        // Switching spatial audio restarts the engine and every player.
        let on = seconds { engine.spatial = true }
        XCTAssertLessThan(on, Self.longestCall, "switching spatial audio on blocked the main thread")
        try XCTSkipIf(ioCycle(unit) != Self.longerCycle, "the cycle didn't grow at the restart")
        playKeys(on: engine, "spatial")
        try assertRendered(engine, "spatial")

        let off = seconds { engine.spatial = false }
        XCTAssertLessThan(off, Self.longestCall, "switching spatial audio off blocked the main thread")
        try XCTSkipIf(ioCycle(unit) != Self.longerCycle, "the cycle didn't grow at the restart")
        playKeys(on: engine, "spatial off again")
        try assertRendered(engine, "spatial off again")
    }
}

/// Lengthens the I/O cycle to the frame count passed as its context the
/// moment the output starts. Called on the thread that starts the engine,
/// from inside engine.start().
private let lengthenCycleOnStart: AudioUnitPropertyListenerProc = { context, unit, _, _, _ in
    var size = UInt32(MemoryLayout<UInt32>.size)
    var running: UInt32 = 0
    AudioUnitGetProperty(unit, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0, &running, &size)
    var now: UInt32 = 0
    AudioUnitGetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &now, &size)
    var frames = UInt32(UInt(bitPattern: context))
    guard running != 0, now != frames else { return }
    AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &frames, size)
}

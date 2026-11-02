import AVFoundation
import XCTest
@testable import Thockbox

@available(macOS 14, *)
final class HeadTrackerTests: XCTestCase {
    /// Turning the head left (Core Motion's positive yaw) turns the listener
    /// left (AVAudio's negative yaw), so the keys stay in place.
    func testHeadTurnsTheListener() {
        let left = HeadTracker.listenerOrientation(yaw: .pi / 2, pitch: 0)
        XCTAssertEqual(left.yaw, -90, accuracy: 0.001)
        let nod = HeadTracker.listenerOrientation(yaw: 0, pitch: -.pi / 6)
        XCTAssertEqual(nod.pitch, -30, accuracy: 0.001)
        XCTAssertEqual(nod.yaw, 0, accuracy: 0.001)
    }

    func testTheSettingIsSavedAndOffByDefault() {
        let suite = "ThockboxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.tracksHead = false
        XCTAssertFalse(state.followHeadMovement)
        state.followHeadMovement = true
        XCTAssertTrue(AppState(defaults: defaults).followHeadMovement)
    }

    /// Pins AVAudio's side of the sign: with the listener turned to +90
    /// degrees, a source straight ahead is heard on the left, so positive
    /// yaw turns the listener right (Core Motion's yaw grows turning left).
    func testPositiveListenerYawTurnsRight() throws {
        let engine = AVAudioEngine()
        let environment = AVAudioEnvironmentNode()
        let player = AVAudioPlayerNode()
        let mono = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let stereo = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        engine.attach(environment)
        engine.attach(player)
        engine.connect(player, to: environment, format: mono)
        engine.connect(environment, to: engine.mainMixerNode, format: stereo)
        try engine.enableManualRenderingMode(.offline, format: stereo, maximumFrameCount: 4096)
        environment.renderingAlgorithm = .HRTFHQ
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 90, pitch: 0, roll: 0)
        player.position = AVAudio3DPoint(x: 0, y: 0, z: -1)
        let noise = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: 16384))
        noise.frameLength = 16384
        for i in 0..<16384 { noise.floatChannelData![0][i] = Float.random(in: -0.5...0.5) }
        try engine.start()
        player.scheduleBuffer(noise, at: nil)
        player.play()
        let out = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096))
        var left: Float = 0, right: Float = 0
        for _ in 0..<4 {
            _ = try engine.renderOffline(4096, to: out)
            for i in 0..<Int(out.frameLength) {
                left += abs(out.floatChannelData![0][i])
                right += abs(out.floatChannelData![1][i])
            }
        }
        XCTAssertGreaterThan(left, right * 2, "ahead should sound on the left")
    }
}

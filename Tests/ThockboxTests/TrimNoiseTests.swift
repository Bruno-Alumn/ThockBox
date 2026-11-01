import AVFoundation
import XCTest
@testable import Thockbox

final class TrimNoiseTests: XCTestCase {
    private let sampleRate = 48_000.0

    /// Builds a stereo buffer from a closure giving the mono value at time t (s).
    private func buffer(seconds: Double, _ value: (Double) -> Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        for i in 0..<Int(frames) {
            let v = value(Double(i) / sampleRate)
            buf.floatChannelData![0][i] = v
            buf.floatChannelData![1][i] = v
        }
        return buf
    }

    /// A 2 kHz click decaying over ~10 ms.
    private func click(_ t: Double) -> Float {
        guard t >= 0 else { return 0 }
        return Float(0.5 * sin(2 * .pi * 2_000 * t) * exp(-t / 0.005))
    }

    /// Low-level noise around -50 dBFS, deterministic.
    private var rng = SeededGenerator(seed: 7)
    private func noise() -> Float { Float.random(in: -0.0045...0.0045, using: &rng) }

    private func peak(_ b: AVAudioPCMBuffer) -> Float {
        (0..<Int(b.frameLength)).reduce(0) { max($0, abs(b.floatChannelData![0][$1])) }
    }

    private func ms(_ b: AVAudioPCMBuffer) -> Double { Double(b.frameLength) / sampleRate * 1000 }

    func testRemovesNoiseTailAndKeepsPeak() {
        let input = buffer(seconds: 0.09) { t in self.click(t - 0.002) + self.noise() }
        let out = SoundEngine.trimNoise(input)
        XCTAssertLessThan(ms(out), 45, "noise tail should be cut")
        XCTAssertEqual(peak(out), peak(input), accuracy: 1e-6, "click peak must not change")
        let last = out.floatChannelData![0][Int(out.frameLength) - 1]
        XCTAssertLessThan(abs(last), 0.001, "ends on a fade, not a hard cut")
    }

    func testLeadingSilenceDoesNotHideTheNoiseFloor() {
        // Digital silence first (like Cardboard ENTER), then click, then noise.
        let input = buffer(seconds: 0.1) { t in
            t < 0.015 ? 0 : self.click(t - 0.015) + self.noise()
        }
        let out = SoundEngine.trimNoise(input)
        XCTAssertLessThan(ms(out), 50)
        XCTAssertEqual(peak(out), peak(input), accuracy: 1e-6)
    }

    func testKeepsASecondHit() {
        // Two knocks 60 ms apart (like Oreo's samples), noise in between.
        let input = buffer(seconds: 0.12) { t in
            self.click(t - 0.002) + 0.8 * self.click(t - 0.062) + self.noise()
        }
        let out = SoundEngine.trimNoise(input)
        XCTAssertGreaterThan(ms(out), 62, "the second hit must survive")
    }

    func testLeavesSoundWithoutAClearClickAlone() {
        // Pure noise: nothing to separate, so nothing is trimmed.
        let input = buffer(seconds: 0.05) { _ in self.noise() }
        XCTAssertEqual(SoundEngine.trimNoise(input).frameLength, input.frameLength)
    }
}

/// Small seeded generator so the noise is the same on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

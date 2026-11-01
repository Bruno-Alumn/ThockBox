import AppKit
import AVFoundation
import os.log

let klog = Logger(subsystem: "io.github.bruno-alumn.thockbox", category: "app")

/// Low-latency sample player. A fixed pool of player nodes (each with its own
/// varispeed unit for per-keystroke pitch randomization) feeds a master EQ
/// (the Tone Pad's tilt filter) and the main mixer.
final class SoundEngine {
    private let engine = AVAudioEngine()
    // Voices fan into a submixer (EQ has only one input bus) before the EQ.
    private let submix = AVAudioMixerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 2)
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

    /// A varispeed resamples continuously whether or not anything is playing
    /// (and even at rate 1.0): 20 of them cost ~9% of a core while idle.
    /// Each voice's varispeed is bypassed while silent and only switched in
    /// for the duration of a keystroke. Pan goes back to center at the same
    /// time: an off-center mixer input keeps a costlier mixing path running
    /// on silence (~3% idle after typing vs ~0.8% centered).
    private final class Voice {
        let player = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
        /// Bumped per scheduled buffer so a stale completion (from a buffer
        /// that was interrupted by a newer one) doesn't bypass a live sound.
        var generation = 0
        var isSounding = false
    }

    private var voices: [Voice] = []
    private var nextVoice = 0
    /// Trimmed key samples last ≤ ~130 ms, so even fast typing keeps only a
    /// few voices busy; idle voices still cost CPU (8: ~0.8%, 20: ~1.2%).
    private let voiceCount = 8
    private var outputDeviceID: AudioDeviceID?
    private var shouldRun = false
    private var isSleeping = false

    /// Decoded buffers keyed by "<packId>/<relativePath>".
    private(set) var buffers: [String: AVAudioPCMBuffer] = [:]
    private var currentPack: SoundPack?
    private var packGain: Float = 1

    /// Master volume, 0...1.
    var volume: Float = 0.55 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    /// Pitch offset applied to every keystroke, in cents (Tone Pad X).
    var pitchOffsetCents: Float = 0
    /// Random pitch spread, in ± cents.
    var pitchVariationCents: Float = 60
    /// Stereo spread amount 0...1 (spatial feel; pans by key position).
    var stereoSpread: Float = 0.7

    init() {
        let lowShelf = eq.bands[0]
        lowShelf.filterType = .lowShelf
        lowShelf.frequency = 250
        lowShelf.gain = 0
        lowShelf.bypass = false
        let highShelf = eq.bands[1]
        highShelf.filterType = .highShelf
        highShelf.frequency = 3_000
        highShelf.gain = 0
        highShelf.bypass = false

        engine.attach(submix)
        engine.attach(eq)
        engine.connect(submix, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        for _ in 0..<voiceCount {
            let v = Voice()
            engine.attach(v.player)
            engine.attach(v.varispeed)
            engine.connect(v.player, to: v.varispeed, format: format)
            engine.connect(v.varispeed, to: submix, format: format)
            v.varispeed.bypass = true
            voices.append(v)
        }
        engine.mainMixerNode.outputVolume = volume
        engine.prepare()

        // The engine stops itself when the output route changes (headphones,
        // Bluetooth, display sleep). Rebuild the output connection and restart.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            klog.notice("output configuration changed")
            self?.restart()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isSleeping = true
            self.engine.stop()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isSleeping = false
            guard !self.engine.isRunning else { return }
            self.restart()
        }
    }

    /// Re-negotiate the mixer→output connection (the hardware format may have
    /// changed) and get every voice playing again.
    private func restart() {
        guard shouldRun, !isSleeping else { return }
        engine.stop()
        let hwFormat = engine.outputNode.outputFormat(forBus: 0)
        if hwFormat.sampleRate > 0 {
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: hwFormat)
        }
        requestLowLatencyIO()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            klog.error("engine restart failed: \(error, privacy: .public)")
            if outputDeviceID != nil {
                setOutputDevice(nil)
            }
            return
        }
        reviveVoices()
        klog.notice("engine restarted (hw \(hwFormat.sampleRate, privacy: .public) Hz, output latency \(self.outputLatency * 1000, privacy: .public) ms)")
    }

    func start() throws {
        shouldRun = true
        guard !engine.isRunning else { return }
        requestLowLatencyIO()
        try engine.start()
        reviveVoices()
        klog.notice("engine started (output latency \(self.outputLatency * 1000, privacy: .public) ms)")
    }

    /// Hardware I/O cycle we ask for, in frames. The HAL default (512 frames,
    /// ~10.7 ms at 48 kHz) suits music playback, but a keystroke scheduled
    /// mid-cycle waits for the next one and then a full cycle more before it
    /// reaches the device: ~17 ms median from scheduleBuffer() to render.
    /// 128 frames brings that to ~5 ms and is still trivial for this graph.
    private static let ioBufferFrames: UInt32 = 128

    /// Applies to this process's I/O only; the device keeps serving other
    /// apps at their own sizes. Must run before the engine starts.
    private func requestLowLatencyIO() {
        guard let unit = engine.outputNode.audioUnit else { return }
        var frames = Self.ioBufferFrames
        let err = AudioUnitSetProperty(unit,
                                       kAudioDevicePropertyBufferFrameSize,
                                       kAudioUnitScope_Global,
                                       0,
                                       &frames,
                                       UInt32(MemoryLayout<UInt32>.size))
        if err != noErr {
            klog.error("could not set I/O buffer to \(frames, privacy: .public) frames: \(err, privacy: .public)")
        }
    }

    /// Time from a sample leaving the engine to it reaching the speaker:
    /// the device's own latency plus its safety offset. Bluetooth outputs
    /// report well over 100 ms here, which no buffer setting can recover.
    var outputLatency: TimeInterval {
        engine.outputNode.presentationLatency
    }

    /// After any engine stop→start cycle, player nodes report a stale
    /// `isPlaying == true` and `play()` alone is a no-op — they render
    /// silence forever. A stop()+play() per node fully revives them.
    private func reviveVoices() {
        for v in voices {
            v.player.stop()
            v.player.play()
        }
    }

    func stop() {
        shouldRun = false
        engine.stop()
    }

    /// Tone Pad: x, y in -1...1. X darkens/brightens via shelf tilt, Y shifts pitch.
    func setTone(x: Float, y: Float) {
        eq.bands[0].gain = -x * 6
        eq.bands[1].gain = x * 6
        pitchOffsetCents = y * 250
    }

    // MARK: - Pack loading

    func load(pack: SoundPack) {
        var newBuffers: [String: AVAudioPCMBuffer] = [:]
        var files = Set<String>()
        for entry in pack.manifest.keys.values {
            entry.down.forEach { files.insert($0) }
            entry.up?.forEach { files.insert($0) }
        }
        for rel in files {
            let url = pack.url.appendingPathComponent(rel)
            if let buf = Self.decode(url: url, to: format) {
                newBuffers["\(pack.id)/\(rel)"] = Self.trimNoise(buf)
            } else {
                klog.error("failed to decode \(url.path, privacy: .public)")
            }
        }
        buffers = newBuffers
        currentPack = pack
        packGain = pow(10, (pack.manifest.gainDb ?? 0) / 20)
    }

    private static func decode(url: URL, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let srcFormat = file.processingFormat
        let capacity = AVAudioFrameCount(file.length)
        guard capacity > 0,
              let src = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: capacity),
              (try? file.read(into: src)) != nil else { return nil }
        if srcFormat == format { return src }
        guard let converter = AVAudioConverter(from: srcFormat, to: format) else { return nil }
        let ratio = format.sampleRate / srcFormat.sampleRate
        let outCapacity = AVAudioFrameCount((Double(src.frameLength) * ratio).rounded(.up)) + 64
        guard let dst = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outCapacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: dst, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return src
        }
        return error == nil ? dst : nil
    }

    /// Strip the recorded room noise before and after the keystroke. Most
    /// samples carry a low-frequency noise floor only ~30 dB under the click
    /// and end abruptly while it's still sounding; overlapping voices during
    /// fast typing stack those tails into an audible hiss/rumble bed.
    /// The room tone is measured from the sample's tail (a leading stretch of
    /// digital silence would otherwise read as the floor). Sound is kept from
    /// the first 2 ms window >6 dB above it until the level settles back near
    /// it for 6 ms after the last real hit, then a 1 ms fade-in and a 10 ms
    /// cosine fade-out are applied.
    static func trimNoise(_ buf: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let data = buf.floatChannelData else { return buf }
        let channels = Int(buf.format.channelCount)
        let frames = Int(buf.frameLength)
        let sr = buf.format.sampleRate
        let hop = max(1, Int(sr * 0.002))
        let windows = frames / hop
        guard windows >= 8 else { return buf }

        var rms = [Float](repeating: 0, count: windows)
        for w in 0..<windows {
            var sum: Float = 0
            for c in 0..<channels {
                let ch = data[c]
                for i in (w * hop)..<((w + 1) * hop) { sum += ch[i] * ch[i] }
            }
            rms[w] = (sum / Float(hop * channels)).squareRoot()
        }
        guard let peakWin = rms.indices.max(by: { rms[$0] < rms[$1] }) else { return buf }
        let peak = rms[peakWin]
        let tail = rms[(windows - max(4, windows / 4))...].sorted()
        let noise = tail[tail.count / 2]
        // No clear click over the room tone: nothing safe to separate.
        guard peak > noise * 2.8 else { return buf } // 9 dB
        let threshold = max(noise * 2, peak * 0.001) // +6 dB, or -60 dB
        guard let firstWin = rms.firstIndex(where: { $0 > threshold }) else { return buf }
        // A later hit well over the room tone (Oreo's second knock) is real
        // sound, so only look for the cut after the last one.
        let lastHit = max(peakWin, rms.lastIndex(where: { $0 > noise * 5.6 }) ?? peakWin) // 15 dB
        let hold = 3 // 6 ms
        var endWin = windows
        for w in (lastHit + 1)..<max(lastHit + 1, windows - hold + 1)
        where rms[w..<(w + hold)].allSatisfy({ $0 < threshold }) {
            endWin = w
            break
        }

        let start = max(0, (firstWin - 1) * hop)
        let keepEnd = min(frames, endWin * hop)
        let end = min(frames, keepEnd + Int(sr * 0.010))
        let length = end - start
        guard length < frames,
              let out = AVAudioPCMBuffer(pcmFormat: buf.format, frameCapacity: AVAudioFrameCount(length)),
              let dst = out.floatChannelData else { return buf }
        out.frameLength = AVAudioFrameCount(length)

        // Only fade in where we cut into the recording; a click that starts
        // on sample 0 keeps its attack.
        let fadeIn = start > 0 ? min(length, Int(sr * 0.001)) : 0
        let fadeOut = end - keepEnd
        for c in 0..<channels {
            let src = data[c], o = dst[c]
            for i in 0..<length {
                var g: Float = 1
                if i < fadeIn { g = Float(i) / Float(fadeIn) }
                let k = i - (length - fadeOut)
                if fadeOut > 0, k >= 0 {
                    g *= 0.5 + 0.5 * cos(Float.pi * Float(k + 1) / Float(fadeOut))
                }
                o[i] = src[start + i] * g
            }
        }
        return out
    }

    // MARK: - Extras (shared one-off samples, e.g. the return-key ding)

    private var extras: [String: AVAudioPCMBuffer] = [:]

    /// Load loose samples from Sounds/_extras/<name>.(wav|mp3|caf|aiff).
    func loadExtras(from dir: URL) {
        extras.removeAll()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where ["wav", "mp3", "caf", "aiff", "m4a"].contains(url.pathExtension) {
            if let buf = Self.decode(url: url, to: format) {
                extras[url.deletingPathExtension().lastPathComponent] = buf
            }
        }
    }

    func playExtra(named name: String, gain: Float = 0.7) {
        guard let buffer = extras[name] else { return }
        play(buffer: buffer, cents: 0, pan: 0.2, gain: gain)
    }

    // MARK: - Playback

    /// Play a keystroke sound. `up` selects release samples; returns false if
    /// the pack has no sample for this class/direction.
    @discardableResult
    func playKey(keyClass: KeyClass, up: Bool, x: Float) -> Bool {
        guard let pack = currentPack else { return false }
        let candidates = pack.samples(for: keyClass, up: up)
        guard !candidates.isEmpty,
              let rel = candidates.randomElement(),
              let buffer = buffers["\(pack.id)/\(rel)"] else {
            if !up {
                klog.error("no sample for \(keyClass.rawValue, privacy: .public) in pack \(pack.id, privacy: .public)")
            }
            return false
        }
        if !engine.isRunning {
            klog.error("play requested but engine not running")
            return false
        }

        let cents = pitchOffsetCents + Float.random(in: -pitchVariationCents...pitchVariationCents)
        let pan = (x - 0.5) * 2 * 0.35 * stereoSpread
        let gain = packGain * (up ? 0.8 : 1.0)
        play(buffer: buffer, cents: cents, pan: pan, gain: gain)
        return true
    }

    /// The next voice in turn that isn't sounding. Only when every voice is
    /// busy (e.g. under a long ding) does the next one in turn get cut off.
    static func voiceIndex(next: Int, count: Int, isBusy: (Int) -> Bool) -> Int {
        (0..<count).lazy.map { (next + $0) % count }.first { !isBusy($0) } ?? next
    }

    private func play(buffer: AVAudioPCMBuffer, cents: Float, pan: Float, gain: Float) {
        guard engine.isRunning else { return }
        let index = Self.voiceIndex(next: nextVoice, count: voiceCount) { voices[$0].isSounding }
        let voice = voices[index]
        nextVoice = (index + 1) % voiceCount
        voice.isSounding = true
        voice.varispeed.rate = pow(2, cents / 1_200)
        voice.varispeed.bypass = false
        voice.player.pan = pan
        voice.player.volume = gain
        voice.generation &+= 1
        let generation = voice.generation
        // .dataRendered, not .dataPlayedBack: the voice is free once its sound
        // has been rendered, and tracking playback out to the speakers cost
        // ~40% of the per-key CPU (`make bench`: ~1,700 -> ~1,100 us/key).
        voice.player.scheduleBuffer(buffer, at: nil, options: .interrupts,
                                    completionCallbackType: .dataRendered) { [weak voice] _ in
            DispatchQueue.main.async {
                guard let voice, voice.generation == generation else { return }
                voice.isSounding = false
                voice.varispeed.bypass = true
                voice.player.pan = 0
            }
        }
        if !voice.player.isPlaying { voice.player.play() }
    }

    // MARK: - Output device

    /// Route audio to a specific output device (nil = system default).
    func setOutputDevice(_ deviceID: AudioDeviceID?) {
        outputDeviceID = deviceID
        shouldRun = true
        engine.stop()
        var id = deviceID ?? AudioDevices.defaultOutputDevice()
        if let unit = engine.outputNode.audioUnit, id != kAudioObjectUnknown {
            let err = AudioUnitSetProperty(unit,
                                           kAudioOutputUnitProperty_CurrentDevice,
                                           kAudioUnitScope_Global,
                                           0,
                                           &id,
                                           UInt32(MemoryLayout<AudioDeviceID>.size))
            if err != noErr {
                klog.error("could not select output device \(id, privacy: .public): \(err, privacy: .public)")
            }
        }
        restart()
    }
}

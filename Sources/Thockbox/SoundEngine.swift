import Accelerate
import AppKit
import AVFoundation
import os.log

let klog = Logger(subsystem: "io.github.bruno-alumn.thockbox", category: "app")

/// Low-latency sample player. A fixed pool of player nodes (each with its own
/// varispeed unit for per-keystroke pitch randomization) feeds a master EQ
/// (the brightness tilt filter) and the main mixer.
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

    /// Spatial mode (headphones): keys come from around the listener in 3D.
    /// Its voices are players straight into an environment node, which
    /// renders them binaurally (HRTF); the player's own rate does the pitch
    /// variation a varispeed does in the normal path. Nothing spatial is
    /// attached while the mode is off, so the normal path costs the same.
    private let environment = AVAudioEnvironmentNode()
    private let monoFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private var spatialVoices: [Voice] = []
    private var nextSpatialVoice = 0
    /// Mono copies of the pack's samples, made the first time each plays in
    /// spatial mode (3D sources must be mono).
    private var monoBuffers: [ObjectIdentifier: AVAudioPCMBuffer] = [:]
    var spatial = false {
        didSet {
            guard spatial != oldValue else { return }
            configureSpatial()
        }
    }
    /// Trimmed key samples last ≤ ~130 ms, so even fast typing keeps only a
    /// few voices busy; idle voices still cost CPU (8: ~0.8%, 20: ~1.2%).
    private let voiceCount = 8
    private var outputDeviceID: AudioDeviceID?
    /// A restart that failed (say, Bluetooth audio not ready after wake) is
    /// tried again a few times before giving up on the device.
    private var restartAttempts = 0
    private var restartRetry: DispatchWorkItem?
    /// Called when the picked device kept failing and sound moved to the
    /// system default, so the owner can record where it actually plays.
    var onFallbackToDefault: (() -> Void)?
    private var shouldRun = false
    private var isSleeping = false

    /// A running engine wakes the CPU every I/O cycle (~2.7 ms) even when
    /// silent: ~0.6% of a core, around the clock. After this long without a
    /// sound it pauses (0% CPU) and the next sound resumes it, which adds
    /// ~8 ms to that one key. Bluetooth outputs never pause: they fade in
    /// after the stream stops and would swallow the first keys.
    static let idlePauseDelay: TimeInterval = 30
    private var lastSound = Date()
    private(set) var isIdlePaused = false
    private var idleTimer: Timer?

    /// Decoded buffers keyed by "<packId>/<relativePath>".
    private(set) var buffers: [String: AVAudioPCMBuffer] = [:]
    /// Recently used sets, decoded and leveled, so switching between apps
    /// with their own sets is instant. Keyed by the set's folder.
    private var decodedSets: [URL: [String: AVAudioPCMBuffer]] = [:]
    private var decodedOrder: [URL] = []
    private static let decodedSetLimit = 4
    private var currentPack: SoundPack?
    private var packGain: Float = 1

    /// Master volume, 0...1.
    var volume: Float = 0.55 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    /// Pitch offset applied to every keystroke, in cents (the Pitch slider).
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
            self.isIdlePaused = false
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
        restartRetry?.cancel()
        restartRetry = nil
        guard shouldRun, !isSleeping else { return }
        isIdlePaused = false
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
            restartAttempts += 1
            if restartAttempts <= 5 {
                let retry = DispatchWorkItem { [weak self] in self?.restart() }
                restartRetry = retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 * pow(2, Double(restartAttempts - 1)),
                                              execute: retry)
            } else {
                restartAttempts = 0
                if outputDeviceID != nil {
                    setOutputDevice(nil)
                    onFallbackToDefault?()
                }
            }
            return
        }
        restartAttempts = 0
        reviveVoices()
        klog.notice("engine restarted (hw \(hwFormat.sampleRate, privacy: .public) Hz, output latency \(self.outputLatency * 1000, privacy: .public) ms)")
    }

    func start() throws {
        shouldRun = true
        startIdleTimer()
        guard !engine.isRunning else { return }
        isIdlePaused = false
        requestLowLatencyIO()
        try engine.start()
        reviveVoices()
        lastSound = Date()
        klog.notice("engine started (output latency \(self.outputLatency * 1000, privacy: .public) ms)")
    }

    /// Checks every 10 s rather than re-arming per key, so typing costs
    /// nothing extra.
    private func startIdleTimer() {
        guard idleTimer == nil else { return }
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.pauseIfIdle() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    func pauseIfIdle(now: Date = Date()) {
        guard engine.isRunning, !isIdlePaused,
              now.timeIntervalSince(lastSound) >= Self.idlePauseDelay,
              outputLatency < 0.05 else { return }
        engine.pause()
        isIdlePaused = true
    }

    private func resumeFromIdle() {
        isIdlePaused = false
        do {
            try engine.start()
        } catch {
            klog.error("engine resume failed: \(error, privacy: .public)")
            restart()
        }
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
    private func configureSpatial() {
        let running = engine.isRunning
        engine.stop()
        if spatial {
            engine.attach(environment)
            environment.renderingAlgorithm = .HRTFHQ
            // Spatial mode is only on with headphones, so say so, rather
            // than leave the node to guess from the output device: rendered
            // for speakers, the 3D effect is lost on headphones.
            environment.outputType = .headphones
            environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
            environment.distanceAttenuationParameters.referenceDistance = 1
            engine.connect(environment, to: submix, fromBus: 0, toBus: submix.nextAvailableInputBus, format: format)
            for _ in 0..<voiceCount {
                let v = Voice()
                engine.attach(v.player)
                engine.connect(v.player, to: environment, format: monoFormat)
                v.player.renderingAlgorithm = .HRTFHQ
                spatialVoices.append(v)
            }
        } else {
            for v in spatialVoices {
                v.player.stop()
                engine.detach(v.player)
            }
            spatialVoices.removeAll()
            engine.detach(environment)
            monoBuffers.removeAll()
        }
        klog.notice("spatial audio \(self.spatial ? "on" : "off", privacy: .public)")
        if running || shouldRun { restart() }
    }

    /// Which way the listener faces in spatial mode, in degrees: head
    /// tracking turns it so keys stay put when the head turns.
    func setListenerOrientation(yaw: Float, pitch: Float) {
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: yaw, pitch: pitch, roll: 0)
    }

    /// Where a key sits around the listener: on an arc in front, about half
    /// a meter away, from 50° left (x = 0) to 50° right (x = 1).
    static func spatialPosition(x: Float, spread: Float) -> AVAudio3DPoint {
        let angle = (x - 0.5) * 2 * (50 * .pi / 180) * spread
        return AVAudio3DPoint(x: sin(angle) * 0.5, y: 0, z: -cos(angle) * 0.5)
    }

    /// A mono copy (the channels averaged) for a 3D source.
    static func mono(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
              let src = buffer.floatChannelData, let dst = out.floatChannelData else { return nil }
        out.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        for i in 0..<frames {
            var sum: Float = 0
            for ch in 0..<channels { sum += src[ch][i] }
            dst[0][i] = sum / Float(channels)
        }
        return out
    }

    private func reviveVoices() {
        for v in spatialVoices {
            v.player.stop()
            v.player.play()
        }
        for v in voices {
            v.player.stop()
            v.player.play()
        }
    }

    func stop() {
        shouldRun = false
        isIdlePaused = false
        idleTimer?.invalidate()
        idleTimer = nil
        engine.stop()
    }

    /// Tone: x, y in -1...1. X (Brightness) darkens/brightens via shelf tilt, Y (Pitch) shifts pitch.
    func setTone(x: Float, y: Float) {
        eq.bands[0].gain = -x * 6
        eq.bands[1].gain = x * 6
        pitchOffsetCents = y * 250
    }

    // MARK: - Pack loading

    /// Forgets decoded sets, after sets were added, removed or changed.
    func forgetDecodedSets() {
        decodedSets.removeAll()
        decodedOrder.removeAll()
    }

    func load(pack: SoundPack) {
        monoBuffers.removeAll()
        if let cached = decodedSets[pack.url] {
            buffers = cached
            currentPack = pack
            packGain = pow(10, (pack.manifest.gainDb ?? 0) / 20)
            decodedOrder.removeAll { $0 == pack.url }
            decodedOrder.append(pack.url)
            return
        }
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
        // Recordings differ by almost 20 dB from pack to pack. Scale each
        // pack so a typical key press lands at the same level, so switching
        // packs doesn't jump in volume. Done once here, so playback is
        // untouched.
        let typical = (pack.manifest.keys["default"]?.down ?? []).compactMap { newBuffers["\(pack.id)/\($0)"] }
        let gain = Self.normalizingGain(for: typical, allPeaks: newBuffers.values.map(Self.samplePeak))
        if gain != 1 {
            newBuffers.values.forEach { Self.scale($0, by: gain) }
        }
        buffers = newBuffers
        decodedSets[pack.url] = newBuffers
        decodedOrder.removeAll { $0 == pack.url }
        decodedOrder.append(pack.url)
        while decodedOrder.count > Self.decodedSetLimit {
            decodedSets[decodedOrder.removeFirst()] = nil
        }
        currentPack = pack
        packGain = pow(10, (pack.manifest.gainDb ?? 0) / 20)
        klog.notice("pack \(pack.id, privacy: .public): loudness gain \(20 * log10(gain), format: .fixed(precision: 1), privacy: .public) dB")
    }

    /// Where a typical key press lands after normalizing: -32 dBFS, about
    /// where the default pack (Cream) already sits.
    static let targetLevel: Float = 0.025

    /// The gain that brings the median key press to `targetLevel`, limited
    /// so no sample in the pack goes above -1 dBFS.
    static func normalizingGain(for typical: [AVAudioPCMBuffer], allPeaks: [Float]) -> Float {
        let levels = typical.map(loudestLevel).filter { $0 > 0 }.sorted()
        guard !levels.isEmpty else { return 1 }
        let median = levels[levels.count / 2]
        let ceiling = 0.89 / max(allPeaks.max() ?? 0, 1e-6)
        return min(targetLevel / median, ceiling)
    }

    /// RMS of the loudest 10 ms of the first channel: the click itself,
    /// regardless of how much quiet surrounds it.
    static func loudestLevel(_ buf: AVAudioPCMBuffer) -> Float {
        guard let data = buf.floatChannelData?[0] else { return 0 }
        let frames = Int(buf.frameLength)
        let window = max(1, Int(buf.format.sampleRate * 0.01))
        guard frames >= window else { return 0 }
        var best: Float = 0
        var start = 0
        while start + window <= frames {
            var rms: Float = 0
            vDSP_rmsqv(data + start, 1, &rms, vDSP_Length(window))
            best = max(best, rms)
            start += window / 2
        }
        return best
    }

    static func samplePeak(_ buf: AVAudioPCMBuffer) -> Float {
        guard let data = buf.floatChannelData else { return 0 }
        var peak: Float = 0
        for ch in 0..<Int(buf.format.channelCount) {
            var channelPeak: Float = 0
            vDSP_maxmgv(data[ch], 1, &channelPeak, vDSP_Length(buf.frameLength))
            peak = max(peak, channelPeak)
        }
        return peak
    }

    static func scale(_ buf: AVAudioPCMBuffer, by gain: Float) {
        guard let data = buf.floatChannelData else { return }
        var gain = gain
        for ch in 0..<Int(buf.format.channelCount) {
            vDSP_vsmul(data[ch], 1, &gain, data[ch], 1, vDSP_Length(buf.frameLength))
        }
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
    /// `velocity` (0...1) scales the gain; see TypingDynamics.
    func playKey(keyClass: KeyClass, up: Bool, x: Float, velocity: Float = 1) -> Bool {
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
        if !engine.isRunning && !isIdlePaused {
            klog.error("play requested but engine not running")
            return false
        }

        let cents = pitchOffsetCents + Float.random(in: -pitchVariationCents...pitchVariationCents)
        let gain = packGain * (up ? 0.8 : 1.0) * velocity
        if spatial {
            playSpatial(buffer: buffer, cents: cents, x: x, gain: gain)
        } else {
            let pan = (x - 0.5) * 2 * 0.35 * stereoSpread
            play(buffer: buffer, cents: cents, pan: pan, gain: gain)
        }
        return true
    }

    /// The next voice in turn that isn't sounding. Only when every voice is
    /// busy (e.g. under a long ding) does the next one in turn get cut off.
    /// Voices still rendering a sound (for tests: they must free up again).
    var busyVoiceCount: Int { (voices + spatialVoices).filter(\.isSounding).count }

    /// The output's render clock in samples, or nil before it has rendered.
    /// Tests use it to tell a slow or stalled audio device (CI runners) from
    /// voices that never free up.
    var renderedSamples: Double? {
        engine.outputNode.lastRenderTime.map { Double($0.sampleTime) }
    }

    static func voiceIndex(next: Int, count: Int, isBusy: (Int) -> Bool) -> Int {
        (0..<count).lazy.map { (next + $0) % count }.first { !isBusy($0) } ?? next
    }

    private func play(buffer: AVAudioPCMBuffer, cents: Float, pan: Float, gain: Float) {
        lastSound = Date()
        if isIdlePaused { resumeFromIdle() }
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

    private func playSpatial(buffer: AVAudioPCMBuffer, cents: Float, x: Float, gain: Float) {
        lastSound = Date()
        if isIdlePaused { resumeFromIdle() }
        guard engine.isRunning, !spatialVoices.isEmpty else { return }
        let key = ObjectIdentifier(buffer)
        guard let mono = monoBuffers[key] ?? Self.mono(buffer, format: monoFormat) else { return }
        monoBuffers[key] = mono
        let index = Self.voiceIndex(next: nextSpatialVoice, count: spatialVoices.count) { spatialVoices[$0].isSounding }
        let voice = spatialVoices[index]
        nextSpatialVoice = (index + 1) % spatialVoices.count
        voice.isSounding = true
        voice.player.rate = pow(2, cents / 1_200)
        voice.player.position = Self.spatialPosition(x: x, spread: stereoSpread)
        voice.player.volume = gain
        voice.generation &+= 1
        let generation = voice.generation
        voice.player.scheduleBuffer(mono, at: nil, options: .interrupts,
                                    completionCallbackType: .dataRendered) { [weak voice] _ in
            DispatchQueue.main.async {
                guard let voice, voice.generation == generation else { return }
                voice.isSounding = false
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

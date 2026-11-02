import AVFoundation

/// Imports a Mechvibes sound pack (github.com/hainguyents13/mechvibes): a
/// folder with a config.json and its audio. Both config formats are read:
///
/// - v2 ("definitions"): keys named like "KeyA" or "Space", each with
///   [[pressStart, pressEnd], [releaseStart, releaseEnd]] in milliseconds,
///   in one shared audio file or a file of its own.
/// - v1 ("defines"): keys as scancodes, each [start, length] in one sprite
///   file ("single") or the name of its own file ("multi").
///
/// Each slice is written out as a WAV in a user pack, so the result loads,
/// trims and loudness-matches like any other switch set.
enum MechvibesPack {
    struct Clip: Hashable {
        let keyClass: KeyClass
        let up: Bool
        let file: String
        /// Milliseconds into `file`; nil means the whole file.
        let span: ClosedRange<Double>?
    }

    static func isPack(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("config.json").path)
    }

    /// The pack's name and every sound it defines, from its config.json.
    static func plan(config data: Data) throws -> (name: String?, clips: [Clip]) {
        guard let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UserPacks.ImportError(errorDescription: "The pack's config.json couldn't be read.")
        }
        let name = config["name"] as? String
        var clips: [Clip] = []

        if let definitions = config["definitions"] as? [String: [String: Any]] {
            let shared = config["audio_file"] as? String
            for (code, definition) in definitions {
                guard let file = definition["audio_file"] as? String ?? shared else { continue }
                let keyClass = keyClass(forCode: code)
                let timing = (definition["timing"] as? [[Double]]) ?? []
                if timing.isEmpty {
                    clips.append(Clip(keyClass: keyClass, up: false, file: file, span: nil))
                }
                for (index, pair) in timing.prefix(2).enumerated() where pair.count == 2 && pair[1] > pair[0] {
                    clips.append(Clip(keyClass: keyClass, up: index == 1, file: file, span: pair[0]...pair[1]))
                }
            }
        } else if let defines = config["defines"] as? [String: Any] {
            let sprite = config["sound"] as? String
            for (code, value) in defines {
                let keyClass = Int(code).map(keyClass(forScancode:)) ?? .default
                if let file = value as? String {
                    clips.append(Clip(keyClass: keyClass, up: false, file: file, span: nil))
                } else if let slice = value as? [Double], slice.count == 2, slice[1] > 0, let sprite {
                    clips.append(Clip(keyClass: keyClass, up: false, file: sprite, span: slice[0]...(slice[0] + slice[1])))
                }
            }
        } else {
            throw UserPacks.ImportError(errorDescription: "This config.json doesn't look like a Mechvibes pack.")
        }
        guard clips.contains(where: { !$0.up }) else {
            throw UserPacks.ImportError(errorDescription: "The pack doesn't define any key sounds.")
        }
        return (name, clips)
    }

    static func importPack(from folder: URL, into directory: URL) throws -> String {
        let plan = try plan(config: Data(contentsOf: folder.appendingPathComponent("config.json")))
        let (id, pack) = try UserPacks.makeFolder(named: plan.name ?? folder.lastPathComponent, in: directory)
        do {
            var audio: [String: AVAudioPCMBuffer] = [:]
            // Many keys share one recording, often across rows; write each
            // slice once and point every key that uses it at the same file.
            struct Slice: Hashable { let file: String; let span: ClosedRange<Double>?; let up: Bool }
            var written: [Slice: String?] = [:]
            var files: [(Clip, String)] = []
            // Community packs often name a file or two that isn't there.
            // Those keys fall back to the pack's other sounds; the import
            // fails only if nothing usable is left.
            var unusable: [String: Error] = [:]
            for clip in plan.clips where unusable[clip.file] == nil {
                let key = Slice(file: clip.file, span: clip.span, up: clip.up)
                if written[key] == nil {
                    let source: AVAudioPCMBuffer
                    do {
                        source = try audio[clip.file] ?? decode(clip.file, in: folder)
                    } catch {
                        klog.error("Mechvibes import: skipping \(clip.file, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        unusable[clip.file] = error
                        continue
                    }
                    audio[clip.file] = source
                    var name: String?
                    if let slice = slice(source, clip.span) {
                        name = "\(clip.up ? "release" : "press")-\(written.count + 1).wav"
                        try write(slice, to: pack.appendingPathComponent(name!))
                    }
                    written[key] = .some(name)
                }
                if let name = written[key] ?? nil { files.append((clip, name)) }
            }
            let manifest: SoundPackManifest
            do {
                manifest = try self.manifest(id: id, name: plan.name ?? folder.lastPathComponent, clips: files)
            } catch {
                // Say what went wrong with the files, not just that no sounds are left.
                throw unusable.sorted { $0.key < $1.key }.first?.value ?? error
            }
            try UserPacks.write(manifest, to: pack)
            return id
        } catch {
            try? FileManager.default.removeItem(at: pack)
            throw error
        }
    }

    /// Specials get their own sounds, rows theirs, and any key without one
    /// draws from every non-special press (and release) sound.
    static func manifest(id: String, name: String, clips: [(Clip, String)]) throws -> SoundPackManifest {
        var down: [KeyClass: [String]] = [:]
        var up: [KeyClass: [String]] = [:]
        let specials: Set<KeyClass> = [.space, .enter, .backspace]
        for (clip, file) in clips {
            var targets = [clip.keyClass]
            if !specials.contains(clip.keyClass) && clip.keyClass != .default { targets.append(.default) }
            for target in targets {
                if clip.up {
                    up[target, default: []].append(file)
                } else {
                    down[target, default: []].append(file)
                }
            }
        }
        guard down[.default]?.isEmpty == false else {
            throw UserPacks.ImportError(errorDescription: "The pack has no sounds for ordinary keys.")
        }
        var keys: [String: SoundPackManifest.KeySounds] = [:]
        for (keyClass, files) in down {
            keys[keyClass.rawValue] = .init(down: Array(Set(files)).sorted(),
                                            up: up[keyClass].map { Array(Set($0)).sorted() })
        }
        return SoundPackManifest(id: id, name: name, attribution: "Imported Mechvibes pack",
                                 license: nil, keys: keys, gainDb: nil)
    }

    // MARK: - Audio

    private static func decode(_ name: String, in folder: URL) throws -> AVAudioPCMBuffer {
        let url = folder.appendingPathComponent(name).standardizedFileURL
        guard url.path.hasPrefix(folder.standardizedFileURL.path + "/"),
              FileManager.default.fileExists(atPath: url.path) else {
            throw UserPacks.ImportError(errorDescription: "The pack's sound file \(name) is missing.")
        }
        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)) else {
                throw UserPacks.ImportError(errorDescription: nil)
            }
            try file.read(into: buffer)
            return buffer
        } catch {
            throw UserPacks.ImportError(errorDescription:
                "Couldn't read \(url.lastPathComponent). This version of macOS may not support its audio format.")
        }
    }

    /// The span's frames with a short fade-out, or nil if it's silent or
    /// too short to be a key.
    static func slice(_ source: AVAudioPCMBuffer, _ span: ClosedRange<Double>?) -> AVAudioPCMBuffer? {
        let rate = source.format.sampleRate
        let total = Int(source.frameLength)
        let start = span.map { min(total, Int($0.lowerBound / 1000 * rate)) } ?? 0
        let end = span.map { min(total, Int($0.upperBound / 1000 * rate)) } ?? total
        let frames = end - start
        guard frames >= Int(rate * 0.005),
              let out = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: AVAudioFrameCount(frames)),
              let from = source.floatChannelData, let to = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(frames)
        let fade = min(frames, Int(rate * 0.003))
        var peak: Float = 0
        for channel in 0..<Int(source.format.channelCount) {
            for i in 0..<frames {
                var sample = from[channel][start + i]
                if i >= frames - fade { sample *= Float(frames - i) / Float(fade) }
                to[channel][i] = sample
                peak = max(peak, abs(sample))
            }
        }
        return peak > 1e-4 ? out : nil
    }

    private static func write(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: buffer.format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: buffer.format.commonFormat,
                                   interleaved: buffer.format.isInterleaved)
        try file.write(from: buffer)
    }

    // MARK: - Key names

    /// v2 names (KeyboardEvent.code) to rows, laid out like a Mac keyboard.
    static func keyClass(forCode code: String) -> KeyClass {
        switch code {
        case "Space": return .space
        case "Enter", "NumpadEnter": return .enter
        case "Backspace", "Delete": return .backspace
        case "Escape", "Backquote", "Minus", "Equal", "IntlBackslash": return .row0
        case "Tab", "BracketLeft", "BracketRight", "Backslash": return .row1
        case "CapsLock", "Semicolon", "Quote": return .row2
        case "ShiftLeft", "ShiftRight", "Comma", "Period", "Slash": return .row3
        case "ControlLeft", "ControlRight", "AltLeft", "AltRight", "MetaLeft", "MetaRight",
             "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Fn": return .row4
        default: break
        }
        if code.hasPrefix("Digit") || (code.hasPrefix("F") && Int(code.dropFirst()) != nil) { return .row0 }
        if code.hasPrefix("Key"), let letter = code.last {
            if "QWERTYUIOP".contains(letter) { return .row1 }
            if "ASDFGHJKL".contains(letter) { return .row2 }
            if "ZXCVBNM".contains(letter) { return .row3 }
        }
        return .default
    }

    /// v1 scancodes (iohook, PC set 1) to rows.
    static func keyClass(forScancode code: Int) -> KeyClass {
        switch code {
        case 57: return .space
        case 28, 3612: return .enter
        case 14, 3667: return .backspace
        case 1...13, 41, 59...68, 87, 88: return .row0
        case 15...27, 43: return .row1
        case 30...40, 58: return .row2
        case 42, 44...54: return .row3
        case 29, 56, 3613, 3640, 3675, 3676, 57416, 57419, 57421, 57424: return .row4
        default: return .default
        }
    }
}

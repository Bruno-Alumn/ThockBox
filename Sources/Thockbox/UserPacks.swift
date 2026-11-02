import AVFoundation
import Foundation

/// Switch sets made from the user's own recordings. Each is a folder in
/// ~/Library/Application Support/ThockBox/Sounds/ with the copied files and
/// a generated pack.json, so it survives app updates and loads like any
/// bundled set (trimming and loudness matching included).
enum UserPacks {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThockBox/Sounds")
    }

    static let audioExtensions: Set<String> = ["wav", "mp3", "caf", "aif", "aiff", "m4a"]

    static func isUserPack(_ pack: SoundPack, in directory: URL = directory) -> Bool {
        pack.url.deletingLastPathComponent().standardizedFileURL.path
            == directory.standardizedFileURL.path
    }

    struct ImportError: LocalizedError {
        let errorDescription: String?
    }

    /// Copies the audio files in `sources` (files, or folders of them) into
    /// a new pack and returns its id. A Mechvibes pack folder (one with a
    /// config.json) is converted instead; see MechvibesPack.
    static func importPack(from sources: [URL], into directory: URL = directory) throws -> String {
        let fm = FileManager.default
        if sources.count == 1 {
            // A dropped config.json or pack.json stands for its folder.
            let name = sources[0].lastPathComponent
            let source = name == "config.json" || name == "pack.json" ? sources[0].deletingLastPathComponent() : sources[0]
            if isThockBoxPack(source) { return try importThockBoxPack(from: source, into: directory) }
            if MechvibesPack.isPack(source) { return try MechvibesPack.importPack(from: source, into: directory) }
        }
        let files = sources.flatMap { source -> [URL] in
            var isFolder: ObjCBool = false
            fm.fileExists(atPath: source.path, isDirectory: &isFolder)
            guard isFolder.boolValue else { return [source] }
            return (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        }
        .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !files.isEmpty else {
            throw ImportError(errorDescription: "No audio files found. Use WAV, MP3, CAF, AIFF or M4A, or a Mechvibes pack folder.")
        }

        // Named after the chosen folder, or the folder the files are in.
        let single = sources.count == 1 ? sources[0] : nil
        let isFolder = single.map { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? false
        let name = (isFolder ? single! : files[0].deletingLastPathComponent()).lastPathComponent
        let (id, folder) = try makeFolder(named: name, in: directory)
        do {
            var copied: [String] = []
            for file in files {
                // Two folders can hold files with the same name.
                var target = file.lastPathComponent
                var suffix = 2
                while copied.contains(target) {
                    target = "\(suffix)-\(file.lastPathComponent)"
                    suffix += 1
                }
                try fm.copyItem(at: file, to: folder.appendingPathComponent(target))
                copied.append(target)
            }
            try write(manifest(id: id, name: name, files: copied), to: folder)
            return id
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
    }

    /// A folder with a pack.json: a set exported from ThockBox, or one made
    /// by hand as described in the README.
    static func isThockBoxPack(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("pack.json").path)
    }

    /// Copies a ThockBox set as it is, under an id of its own so it never
    /// replaces a set you already have.
    private static func importThockBoxPack(from source: URL, into directory: URL) throws -> String {
        let data = try Data(contentsOf: source.appendingPathComponent("pack.json"))
        guard var manifest = try? JSONDecoder().decode(SoundPackManifest.self, from: data),
              manifest.keys[KeyClass.default.rawValue]?.down.isEmpty == false else {
            throw ImportError(errorDescription: "This folder's pack.json isn't a valid ThockBox switch set.")
        }
        let unusable = unusableFiles(in: manifest, at: source)
        guard unusable.isEmpty else {
            let more = unusable.count > 1 ? " and \(unusable.count - 1) more" : ""
            throw ImportError(errorDescription: "This set lists sounds that are missing or can't be played: \(unusable[0])\(more).")
        }
        let (id, folder) = try makeFolder(named: manifest.name, in: directory)
        do {
            let fm = FileManager.default
            for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            where item.lastPathComponent != "pack.json" {
                try fm.copyItem(at: item, to: folder.appendingPathComponent(item.lastPathComponent))
            }
            manifest.id = id
            try write(manifest, to: folder)
            return id
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// The files a manifest lists that don't exist inside `folder` or can't
    /// be opened as audio, so a set that would play nothing isn't added.
    static func unusableFiles(in manifest: SoundPackManifest, at folder: URL) -> [String] {
        let root = folder.standardizedFileURL.path + "/"
        let listed = Set(manifest.keys.values.flatMap { $0.down + ($0.up ?? []) })
        return listed.sorted().filter { name in
            let url = folder.appendingPathComponent(name).standardizedFileURL
            guard url.path.hasPrefix(root) else { return true }
            return (try? AVAudioFile(forReading: url)) == nil
        }
    }

    /// Copies a set into `destination` as a folder named after it, ready
    /// to share and to add again with Add Your Own. Returns the folder.
    @discardableResult
    static func export(_ pack: SoundPack, to destination: URL) throws -> URL {
        let fm = FileManager.default
        var target = destination.appendingPathComponent(pack.name)
        var suffix = 2
        while fm.fileExists(atPath: target.path) {
            target = destination.appendingPathComponent("\(pack.name) \(suffix)")
            suffix += 1
        }
        try fm.copyItem(at: pack.url, to: target)
        return target
    }

    /// A new, empty pack folder with an id made from `name` ("My Board" →
    /// "user-my-board", then "user-my-board-2" if that's taken).
    static func makeFolder(named name: String, in directory: URL) throws -> (id: String, url: URL) {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let slug = String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
            .split(separator: "-").joined(separator: "-")
        let base = "user-" + (slug.isEmpty ? "switches" : slug)
        var id = base
        var suffix = 2
        while fm.fileExists(atPath: directory.appendingPathComponent(id).path) {
            id = "\(base)-\(suffix)"
            suffix += 1
        }
        let folder = directory.appendingPathComponent(id)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        return (id, folder)
    }

    static func write(_ manifest: SoundPackManifest, to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent("pack.json"))
    }

    /// Sorts files by name: "space", "enter"/"return" and "backspace"/
    /// "delete" play for those keys, and "up"/"release" mark the sound of a
    /// key being let go. Everything else is a press sound for any key.
    static func manifest(id: String, name: String, files: [String]) throws -> SoundPackManifest {
        var down: [KeyClass: [String]] = [:]
        var up: [KeyClass: [String]] = [:]
        for file in files {
            let words = Set((file as NSString).deletingPathExtension.lowercased()
                .split(whereSeparator: { !$0.isLetter }).map(String.init))
            let keyClass: KeyClass
            if words.contains("space") || words.contains("spacebar") {
                keyClass = .space
            } else if words.contains("enter") || words.contains("return") {
                keyClass = .enter
            } else if words.contains("backspace") || words.contains("delete") {
                keyClass = .backspace
            } else {
                keyClass = .default
            }
            if words.contains("up") || words.contains("release") || words.contains("released") {
                up[keyClass, default: []].append(file)
            } else {
                down[keyClass, default: []].append(file)
            }
        }
        // A key with only release sounds would be silent when pressed, so
        // those join the general release sounds instead.
        for (keyClass, files) in up where keyClass != .default && down[keyClass] == nil {
            up[.default, default: []] += files
            up[keyClass] = nil
        }
        guard !down.isEmpty else {
            throw ImportError(errorDescription: "Only release sounds were found. Add at least one key-press recording.")
        }
        // Without general press sounds, letters would be silent: use
        // everything that was found.
        if down[.default] == nil { down[.default] = down.values.flatMap { $0 }.sorted() }

        var keys: [String: SoundPackManifest.KeySounds] = [:]
        for (keyClass, files) in down {
            keys[keyClass.rawValue] = .init(down: files, up: up[keyClass])
        }
        return SoundPackManifest(id: id, name: name, attribution: nil, license: nil, keys: keys, gainDb: nil)
    }

    /// Moves a user pack's folder to the Trash.
    static func remove(_ pack: SoundPack) throws {
        try FileManager.default.trashItem(at: pack.url, resultingItemURL: nil)
    }
}

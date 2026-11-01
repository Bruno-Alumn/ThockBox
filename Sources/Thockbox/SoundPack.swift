import Foundation

/// Manifest describing one switch sound set. Lives as `pack.json` inside the
/// pack's folder under Resources/Sounds/<id>/.
struct SoundPackManifest: Codable {
    struct KeySounds: Codable {
        var down: [String]
        var up: [String]?
    }

    var id: String
    var name: String
    var attribution: String?
    var license: String?
    /// Map of KeyClass raw value -> sample files (relative to pack folder).
    /// "default" is required; other classes fall back to it.
    var keys: [String: KeySounds]
    /// Optional master gain trim for this pack, in decibels.
    var gainDb: Float?
}

struct SoundPack: Identifiable {
    let manifest: SoundPackManifest
    let url: URL

    var id: String { manifest.id }
    var name: String { manifest.name }

    /// Resolve the sample list for a key class and stroke direction, falling
    /// back per-direction to the default class when the pack has no specific
    /// mapping (a class may define only `down` and inherit `default`'s `up`).
    func samples(for keyClass: KeyClass, up: Bool) -> [String] {
        let entry = manifest.keys[keyClass.rawValue]
        let fallback = manifest.keys[KeyClass.default.rawValue]
        if up { return entry?.up ?? fallback?.up ?? [] }
        return entry?.down ?? fallback?.down ?? []
    }

    static func discover(in soundsDir: URL) -> [SoundPack] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: soundsDir,
                                                        includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        var packs: [SoundPack] = []
        // Sorted so that, with duplicate ids, the same folder always wins.
        for dir in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let manifestURL = dir.appendingPathComponent("pack.json")
            // Folders without a manifest (e.g. _extras) aren't packs.
            guard fm.fileExists(atPath: manifestURL.path) else { continue }
            let name = dir.lastPathComponent
            let manifest: SoundPackManifest
            do {
                manifest = try JSONDecoder().decode(SoundPackManifest.self,
                                                    from: Data(contentsOf: manifestURL))
            } catch {
                klog.error("skipping pack \(name, privacy: .public): bad pack.json: \(error, privacy: .public)")
                continue
            }
            // Without default press sounds most keys would be silent.
            guard manifest.keys[KeyClass.default.rawValue]?.down.isEmpty == false else {
                klog.error("skipping pack \(name, privacy: .public): no \"default\" sounds")
                continue
            }
            guard !packs.contains(where: { $0.id == manifest.id }) else {
                klog.error("skipping pack \(name, privacy: .public): duplicate id \(manifest.id, privacy: .public)")
                continue
            }
            packs.append(SoundPack(manifest: manifest, url: dir))
        }
        return packs.sorted { $0.name < $1.name }
    }
}

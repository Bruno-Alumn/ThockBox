import AppKit
import Foundation
import Security

/// A GitHub release, as much of it as the updater needs.
struct Release: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let pageURL: URL
    let notes: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
        case notes = "body"
        case assets
    }

    /// "v1.2.0" → "1.2.0".
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    /// The notes as a few plain lines for Settings, one per change. Release
    /// notes are the version's CHANGELOG.md section: "- " bullets that wrap
    /// onto indented lines, with **bold** lead-ins. Older releases have
    /// GitHub's generated "* Title by @user in <PR link>" lines instead.
    var notesPreview: String? {
        var items: [String] = []
        for raw in (notes ?? "").components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("**Full Changelog**") else { continue }
            if let by = line.range(of: " by @", options: .backwards) { line = String(line[..<by.lowerBound]) }
            line = line.replacingOccurrences(of: "**", with: "")
            if line.hasPrefix("* ") || line.hasPrefix("- ") {
                items.append("• " + line.dropFirst(2))
            } else if let last = items.popLast() {
                // A bullet that wraps onto the next lines.
                items.append(last + " " + line)
            } else {
                items.append(line)
            }
        }
        return items.isEmpty ? nil : items.joined(separator: "\n")
    }

    /// The app's download: the disk image `make release` publishes
    /// (ThockBox-<version>.dmg), or a zip from an older release.
    var appArchive: Asset? {
        let ours = assets.filter { $0.name.hasPrefix("ThockBox") }
        return ours.first { $0.name.hasSuffix(".dmg") } ?? ours.first { $0.name.hasSuffix(".zip") }
    }
}

enum AppVersion {
    /// The running app's version, from Info.plist.
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Compares dotted version numbers: "1.10" is newer than "1.9", and
    /// "1.0" equals "1.0.0". Anything after a "-" is ignored.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        let core = version.split(separator: "-", maxSplits: 1).first ?? ""
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}

/// Checks GitHub for a newer release and installs it in place: download the
/// zip, check it's a signed ThockBox of the expected version, swap it in for
/// the running app and relaunch.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading
        case installing
        case failed(String)
        /// Installing didn't work; the release is kept so the user can
        /// retry or download it by hand.
        case installFailed(Release, String)
    }

    @Published private(set) var status: Status = .idle
    @Published var checksAutomatically: Bool {
        didSet {
            defaults.set(checksAutomatically, forKey: "checkForUpdates")
            scheduleChecks()
        }
    }

    var availableRelease: Release? {
        switch status {
        case .available(let release), .installFailed(let release, _): return release
        default: return nil
        }
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private let currentVersion: String
    private var timer: Timer?

    /// The GitHub API. Debug builds can point it elsewhere with the
    /// `updateFeedURL` default, for testing against a local server; release
    /// builds ignore it, so another program can't redirect updates.
    private var feedURL: URL {
        #if DEBUG
        if let custom = defaults.string(forKey: "updateFeedURL").flatMap(URL.init(string:)) {
            return custom
        }
        #endif
        return URL(string: "https://api.github.com/repos/Bruno-Alumn/ThockBox/releases/latest")!
    }

    init(defaults: UserDefaults = .standard, session: URLSession = .shared,
         currentVersion: String = AppVersion.current) {
        self.defaults = defaults
        self.session = session
        self.currentVersion = currentVersion
        defaults.register(defaults: ["checkForUpdates": true])
        checksAutomatically = defaults.bool(forKey: "checkForUpdates")
    }

    func startUp() {
        scheduleChecks()
    }

    /// At most one automatic check a day. The hourly timer only looks at
    /// when the last check was, so a Mac that sleeps a lot still checks.
    private func scheduleChecks() {
        timer?.invalidate()
        timer = nil
        guard checksAutomatically else { return }
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        let last = defaults.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= 86_400 else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        switch status {
        case .checking, .downloading, .installing: return
        default: break
        }
        status = .checking
        do {
            let release = try await fetchLatest()
            defaults.set(Date(), forKey: "lastUpdateCheck")
            if let release, AppVersion.isNewer(release.version, than: currentVersion) {
                status = .available(release)
            } else {
                status = .upToDate
            }
        } catch {
            klog.error("update check failed: \(error.localizedDescription, privacy: .public)")
            // A failed background check isn't worth showing; a manual one is.
            status = userInitiated ? .failed(Self.checkFailure(error)) : .idle
        }
    }

    /// What a failed manual check says, by what actually went wrong.
    static func checkFailure(_ error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed:
                return "Your Mac isn't connected to the internet."
            case .timedOut:
                return "GitHub took too long to answer. Try again later."
            default:
                return "Couldn't reach GitHub. Try again later."
            }
        }
        if let error = error as? HTTPStatusError {
            switch error.code {
            case 403, 429:
                return "GitHub is limiting update checks from your network. Try again in an hour."
            case 500...:
                return "GitHub isn't working right now. Try again later."
            default:
                return "GitHub returned an error (\(error.code)). Try again later."
            }
        }
        return "GitHub's answer couldn't be read. Try again later."
    }

    /// The latest published release, or nil when the repo has none yet.
    private func fetchLatest() async throws -> Release? {
        var request = URLRequest(url: feedURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ThockBox/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard code == 200 else { throw HTTPStatusError(code: code) }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    func install(_ release: Release) async {
        let target = Bundle.main.bundleURL
        // Without a zip to install, or when not running from an app bundle
        // (`swift run`), send the user to the release page instead.
        guard let archive = release.appArchive, target.pathExtension == "app" else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        status = .downloading
        do {
            let (download, response) = try await session.download(from: archive.downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError("The download failed.")
            }
            // A scratch folder on the same volume as the app, so the final
            // swap is a rename rather than a copy.
            let work = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                   appropriateFor: target, create: true)
            defer { try? FileManager.default.removeItem(at: work) }
            let file = work.appendingPathComponent("update." + (archive.name as NSString).pathExtension)
            try FileManager.default.moveItem(at: download, to: file)
            status = .installing
            // hdiutil, ditto and codesign take seconds: off the main thread,
            // so typing keeps its sound and the menu stays responsive.
            let version = release.version
            let (newApp, signedByUs, sameCertificate) = try await Task.detached {
                let app = try Self.unpack(file, in: work, expecting: version)
                return (app, Self.satisfiesOwnRequirement(app), Self.hasOwnCertificate(app))
            }.value
            // macOS keeps a grant only for builds that meet the requirement
            // recorded when it was granted. Builds up to 1.11.3 recorded one
            // naming only the "ThockBox Signing" certificate, so the first
            // update to a Developer ID build loses Accessibility even though
            // it meets today's requirement. Only an update signed by the same
            // certificate is sure to keep it.
            let keepsGrant = signedByUs && sameCertificate
            guard Self.accepts(signedByUs: signedByUs, runningAdHoc: Self.isAdHocSigned) else {
                throw UpdateError("The download isn't signed by ThockBox's release certificate.")
            }

            do {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp)
            } catch CocoaError.fileWriteNoPermission {
                throw UpdateError("ThockBox doesn't have permission to replace itself in \(target.deletingLastPathComponent().lastPathComponent).")
            }
            klog.notice("updated to \(release.version, privacy: .public), keeps grant: \(keepsGrant, privacy: .public)")
            // If the new build isn't signed by the same certificate (an ad-hoc
            // build, or the first update to a Developer ID release), the old
            // grant would quietly do nothing, so clear it and let the new
            // build ask, with Settings open to explain why.
            if !keepsGrant, let id = Bundle.main.bundleIdentifier {
                try? Self.run("/usr/bin/tccutil", ["reset", "Accessibility", id])
                defaults.set(true, forKey: "showSettingsAfterUpdate")
            }
            relaunch(target)
        } catch {
            klog.error("update failed: \(error.localizedDescription, privacy: .public)")
            status = .installFailed(release, (error as? UpdateError)?.message ?? "The update couldn't be installed.")
        }
    }

    /// Takes the app out of the download (a disk image or a zip) and checks
    /// it's a signed ThockBox of the version the release says, before
    /// anything touches the installed app.
    /// Ways to mount a disk image, tried in order. hdiutil works on every
    /// supported macOS; macOS 27 marks `hdiutil attach` deprecated in favor
    /// of `diskutil image attach` (which older versions lack), so that's the
    /// fallback. Both print the same plist.
    nonisolated static let attachCommands: [(tool: String, arguments: [String])] = [
        ("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-plist"]),
        ("/usr/sbin/diskutil", ["image", "attach", "--plist", "--readOnly", "--nobrowse"]),
    ]

    /// Mounts `image` read-only and out of sight in Finder, and returns
    /// where. The system picks the mount point (a volume mounted inside the
    /// temporary items folder can't be read).
    nonisolated static func attach(_ image: URL, using commands: [(tool: String, arguments: [String])] = attachCommands)
        throws -> URL {
        for (tool, arguments) in commands where FileManager.default.isExecutableFile(atPath: tool) {
            guard let info = try? output(tool, arguments + [image.path]) else { continue }
            let entities = (try? PropertyListSerialization.propertyList(from: info, format: nil)
                as? [String: Any])?["system-entities"] as? [[String: Any]] ?? []
            if let mountPath = entities.lazy.compactMap({ $0["mount-point"] as? String }).first {
                return URL(fileURLWithPath: mountPath)
            }
        }
        throw UpdateError("The download couldn't be opened.")
    }

    nonisolated static func unpack(_ download: URL, in work: URL, expecting version: String) throws -> URL {
        let out = work.appendingPathComponent("unpacked")
        if download.pathExtension == "dmg" {
            // Mounted just long enough to copy the app out.
            let mount = try attach(download)
            defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
            let apps = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "app" }
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            do {
                for app in apps {
                    try run("/usr/bin/ditto", [app.path, out.appendingPathComponent(app.lastPathComponent).path])
                }
            } catch {
                throw UpdateError("The download couldn't be unpacked.")
            }
        } else {
            do {
                try run("/usr/bin/ditto", ["-x", "-k", download.path, out.path])
            } catch {
                throw UpdateError("The download couldn't be unpacked.")
            }
        }
        let apps = try FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first, let bundle = Bundle(url: app) else {
            throw UpdateError("The download doesn't contain the app.")
        }
        guard bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else {
            throw UpdateError("The download doesn't match the release.")
        }
        do {
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        } catch {
            throw UpdateError("The download's signature is invalid.")
        }
        return app
    }

    /// Opens the new copy, then quits.
    private func relaunch(_ app: URL) {
        Relaunch.now(app) { [weak self] _ in
            self?.status = .failed("Updated. Quit and reopen ThockBox to finish.")
        }
    }

    /// Whether to install a download. A valid signature isn't enough: it has
    /// to be ThockBox's own (the running app's designated requirement, which
    /// names the release certificate), or anyone able to publish a release
    /// asset could ship code. Ad-hoc builds (made locally without the
    /// certificate) have no identity to compare against, so they accept any
    /// valid signature and the update asks for Accessibility access again.
    /// Releases carry one requirement that accepts both the old "ThockBox
    /// Signing" certificate and the maintainer's Developer ID
    /// (packaging/designated_requirement.txt), so updates move between the
    /// two without a manual download.
    nonisolated static func accepts(signedByUs: Bool, runningAdHoc: Bool) -> Bool {
        signedByUs || runningAdHoc
    }

    /// Whether `app` meets the running app's designated requirement, the
    /// same check macOS uses to decide if an Accessibility grant still
    /// applies. Ad-hoc requirements name an exact build, so this is false
    /// whenever the running app is ad-hoc signed.
    nonisolated static func satisfiesOwnRequirement(_ app: URL) -> Bool {
        var me: SecCode?
        var staticMe: SecStaticCode?
        var requirement: SecRequirement?
        var other: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &staticMe) == errSecSuccess, let staticMe,
              SecCodeCopyDesignatedRequirement(staticMe, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &other) == errSecSuccess, let other else {
            return false
        }
        return SecStaticCodeCheckValidity(other, [], requirement) == errSecSuccess
    }

    /// Whether `app` is signed with the same leaf certificate as the
    /// running app. False if either can't be read, or for ad-hoc signatures,
    /// which have no certificate.
    nonisolated static func hasOwnCertificate(_ app: URL) -> Bool {
        var me: SecCode?
        var staticMe: SecStaticCode?
        var other: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &staticMe) == errSecSuccess, let staticMe,
              SecStaticCodeCreateWithPath(app as CFURL, [], &other) == errSecSuccess, let other,
              let mine = leafCertificate(staticMe), let theirs = leafCertificate(other) else {
            return false
        }
        return mine == theirs
    }

    private nonisolated static func leafCertificate(_ code: SecStaticCode) -> Data? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &info) == errSecSuccess,
              let certificates = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return nil }
        return SecCertificateCopyData(leaf) as Data
    }

    /// Whether this build is ad-hoc signed, so an update will need the
    /// Accessibility grant again. If the signature can't be read it answers
    /// no, so the updater insists on the release certificate (fails closed)
    /// rather than accepting any signature.
    static var isAdHocSigned: Bool {
        var me: SecCode?
        var staticMe: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &staticMe) == errSecSuccess, let staticMe,
              SecCodeCopySigningInformation(staticMe, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &info) == errSecSuccess,
              let flags = (info as? [String: Any])?[kSecCodeInfoFlags as String] as? UInt32 else {
            return false
        }
        return flags & SecCodeSignatureFlags.adhoc.rawValue != 0
    }

    /// Runs a tool and returns what it printed.
    nonisolated static func output(_ tool: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError("\((tool as NSString).lastPathComponent) failed")
        }
        return data
    }

    nonisolated static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError("\((tool as NSString).lastPathComponent) failed")
        }
    }
}

struct UpdateError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

struct HTTPStatusError: LocalizedError {
    let code: Int
    var errorDescription: String? { "GitHub returned HTTP \(code)" }
}

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

    /// The app archive made by `make zip` (ThockBox-<version>.zip).
    var appArchive: Asset? {
        assets.first { $0.name.hasPrefix("ThockBox") && $0.name.hasSuffix(".zip") }
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
    }

    @Published private(set) var status: Status = .idle
    @Published var checksAutomatically: Bool {
        didSet {
            defaults.set(checksAutomatically, forKey: "checkForUpdates")
            scheduleChecks()
        }
    }

    var availableRelease: Release? {
        if case .available(let release) = status { return release }
        return nil
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private var timer: Timer?

    /// The GitHub API by default. The `updateFeedURL` default points it
    /// elsewhere, for testing against a local server.
    private var feedURL: URL {
        defaults.string(forKey: "updateFeedURL").flatMap(URL.init(string:))
            ?? URL(string: "https://api.github.com/repos/Bruno-Alumn/ThockBox/releases/latest")!
    }

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
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
            if let release, AppVersion.isNewer(release.version, than: AppVersion.current) {
                status = .available(release)
            } else {
                status = .upToDate
            }
        } catch {
            klog.error("update check failed: \(error.localizedDescription, privacy: .public)")
            // A failed background check isn't worth showing; a manual one is.
            status = userInitiated ? .failed("Couldn't reach GitHub. Try again later.") : .idle
        }
    }

    /// The latest published release, or nil when the repo has none yet.
    private func fetchLatest() async throws -> Release? {
        var request = URLRequest(url: feedURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ThockBox/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard code == 200 else { throw UpdateError("GitHub returned HTTP \(code)") }
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
            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: download, to: zip)
            status = .installing
            let newApp = try unpack(zip, in: work, expecting: release.version)

            let keepsGrant = Self.satisfiesOwnRequirement(newApp)
            _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp)
            klog.notice("updated to \(release.version, privacy: .public), keeps grant: \(keepsGrant, privacy: .public)")
            // macOS keeps the Accessibility grant when the new build is
            // signed by the same identity. If it isn't (an ad-hoc build, or
            // the first update after switching identities), the old grant
            // would quietly do nothing, so clear it and let the new build ask.
            if !keepsGrant, let id = Bundle.main.bundleIdentifier {
                try? Self.run("/usr/bin/tccutil", ["reset", "Accessibility", id])
                defaults.set(true, forKey: "showSettingsAfterUpdate")
            }
            relaunch(target)
        } catch {
            klog.error("update failed: \(error.localizedDescription, privacy: .public)")
            status = .failed((error as? UpdateError)?.message ?? "The update couldn't be installed.")
        }
    }

    /// Unzips the download and checks it's a signed ThockBox of the version
    /// the release says, before anything touches the installed app.
    private func unpack(_ zip: URL, in work: URL, expecting version: String) throws -> URL {
        let out = work.appendingPathComponent("unpacked")
        try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path])
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
            try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        } catch {
            throw UpdateError("The download's signature is invalid.")
        }
        return app
    }

    /// Opens the new copy once this process has exited, then quits.
    private func relaunch(_ app: URL) {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open \"$0\"", app.path]
        do {
            try shell.run()
            NSApp.terminate(nil)
        } catch {
            status = .failed("Updated. Quit and reopen ThockBox to finish.")
        }
    }

    /// Whether `app` meets the running app's designated requirement, the
    /// same check macOS uses to decide if an Accessibility grant still
    /// applies. Ad-hoc requirements name an exact build, so this is false
    /// whenever the running app is ad-hoc signed.
    static func satisfiesOwnRequirement(_ app: URL) -> Bool {
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

    /// Whether this build is ad-hoc signed, so an update will need the
    /// Accessibility grant again.
    static var isAdHocSigned: Bool {
        var me: SecCode?
        var staticMe: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &staticMe) == errSecSuccess, let staticMe,
              SecCodeCopySigningInformation(staticMe, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &info) == errSecSuccess,
              let flags = (info as? [String: Any])?[kSecCodeInfoFlags as String] as? UInt32 else {
            return true
        }
        return flags & SecCodeSignatureFlags.adhoc.rawValue != 0
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
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

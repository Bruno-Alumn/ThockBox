import AppKit
import SwiftUI

/// The release notes for one version, read from the CHANGELOG.md bundled
/// with the app, so the window always matches what shipped.
struct WhatsNew: Equatable {
    let version: String
    /// One entry per bullet, as Markdown (bold and code spans).
    let items: [String]

    private static let lastVersionKey = "lastLaunchedVersion"

    /// The section for `version`, or the newest released one when `version`
    /// is nil. Nil if there's no such section.
    static func parse(changelog: String, version: String? = nil) -> WhatsNew? {
        var found: String?
        var items: [String] = []
        for line in changelog.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                if found != nil { break }
                let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let released = heading.first?.isNumber ?? false
                if heading == version || (version == nil && released) { found = heading }
            } else if found != nil {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("- ") {
                    items.append(String(line.dropFirst(2)))
                } else if !trimmed.isEmpty, let last = items.popLast() {
                    // A bullet that wraps onto the next lines.
                    items.append(last + " " + trimmed)
                }
            }
        }
        guard let found, !items.isEmpty else { return nil }
        return WhatsNew(version: found, items: items)
    }

    /// Everything new since `last`, up to and including `current`, newest
    /// first, so skipping a version (1.2.0 straight to 1.2.2) still shows
    /// what the skipped one brought. Just `current` when `last` is unknown.
    static func since(changelog: String, after last: String?, upTo current: String) -> WhatsNew? {
        // An unknown or non-numeric last version (a beta, a dev build): just
        // this version's notes.
        guard let last, isNewer(last, than: "0") else { return parse(changelog: changelog, version: current) }
        let versions = changelog.components(separatedBy: .newlines)
            .filter { $0.hasPrefix("## ") }
            .map { String($0.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
            .filter { isNewer($0, than: last) && !isNewer($0, than: current) }
        let items = versions.compactMap { parse(changelog: changelog, version: $0)?.items }.flatMap { $0 }
        return items.isEmpty ? nil : WhatsNew(version: current, items: items)
    }

    /// Whether a note is a fix ("Fixed: …", or in bold, "**Fixed on macOS
    /// 27:** …") rather than something new; the window marks the two with
    /// different icons.
    static func isFix(_ item: String) -> Bool {
        item.hasPrefix("Fixed") || item.hasPrefix("**Fixed")
    }

    /// Compares dotted version numbers ("1.10.0" is newer than "1.9.2").
    /// Headings that aren't version numbers ("Unreleased") are never newer.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int]? {
            let parts = v.split(separator: ".").map { Int($0) }
            return parts.contains(nil) || parts.isEmpty ? nil : parts.compactMap { $0 }
        }
        guard let x = parts(a), let y = parts(b) else { return false }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static var bundledChangelog: String? {
        Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    static func bundled(version: String? = nil) -> WhatsNew? {
        bundledChangelog.flatMap { parse(changelog: $0, version: version) }
    }

    /// Only after an update: not on a new install, and not when the version
    /// is the same as last launch.
    static func isUpdate(lastVersion: String?, current: String, usedBefore: Bool) -> Bool {
        if let lastVersion { return lastVersion != current }
        // Versions before this one didn't record themselves.
        return usedBefore
    }

    /// Records this launch's version; returns the notes to show, if this
    /// launch is the first after an update and the notes cover it.
    static func afterLaunch(defaults: UserDefaults = .standard, usedBefore: Bool) -> WhatsNew? {
        guard let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return nil }
        let last = defaults.string(forKey: lastVersionKey)
        defaults.set(current, forKey: lastVersionKey)
        guard isUpdate(lastVersion: last, current: current, usedBefore: usedBefore) else { return nil }
        return bundledChangelog.flatMap { since(changelog: $0, after: last, upTo: current) }
    }
}

@MainActor
final class WhatsNewWindow: NSObject, NSWindowDelegate {
    static let shared = WhatsNewWindow()

    private var window: NSWindow?

    /// The notes for this version, or the newest ones when it has none.
    func show(_ notes: WhatsNew? = nil) {
        guard let notes = notes ?? WhatsNew.bundled() else { return }
        window?.close()
        let host = NSHostingController(rootView: WhatsNewView(notes: notes) { [weak self] in
            self?.window?.close()
        })
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "What's New in ThockBox"
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        NSApp.setActivationPolicy(.regular)
        // Its full size before centering: SwiftUI sizes the window later,
        // and it would grow down from a spot picked for a smaller one,
        // under the Dock on a short screen.
        window.setContentSize(window.contentViewController?.view.fittingSize ?? window.frame.size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        MainWindow.backToMenuBar(closing: notification.object as? NSWindow)
    }
}

struct WhatsNewView: View {
    let notes: WhatsNew
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WindowHeader(state: AppState.shared, title: "What's New", subtitle: "ThockBox \(notes.version)")

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(notes.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 12) {
                            let fix = WhatsNew.isFix(item)
                            SettingsIcon(symbol: fix ? "wrench.and.screwdriver.fill" : "sparkles",
                                         color: fix ? .gray : .orange, size: 22)
                            Text(LocalizedStringKey(item))
                                .fixedSize(horizontal: false, vertical: true)
                                // Lines the first line up with the icon's middle.
                                .padding(.top, 3)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Link("All Release Notes", destination: URL(string: "https://github.com/Bruno-Alumn/ThockBox/releases")!)
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
    }
}

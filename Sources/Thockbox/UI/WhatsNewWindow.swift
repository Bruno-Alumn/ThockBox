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

    static func bundled(version: String? = nil) -> WhatsNew? {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(changelog: text, version: version)
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
        return bundled(version: current)
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
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        NSApp.setActivationPolicy(.regular)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What's New")
                        .font(.title2.bold())
                    Text("ThockBox \(notes.version)")
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(notes.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.secondary)
                            Text(LocalizedStringKey(item))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Link("All Release Notes", destination: URL(string: "https://github.com/Bruno-Alumn/ThockBox/releases")!)
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

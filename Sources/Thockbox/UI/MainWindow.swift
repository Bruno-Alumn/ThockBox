import AppKit
import SwiftUI

/// The settings window, laid out like System Settings: a sidebar of pages
/// with colored icons, and the page's grouped form beside it. ThockBox
/// normally lives only in the menu bar (LSUIElement); while this window is
/// open it also shows a Dock icon and app menu, like a regular app, and goes
/// back to menu-bar-only on close.
@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    static let shared = MainWindow()

    private var window: NSWindow?
    let navigation = SettingsNavigation()

    /// Brings up the window, on `page` if given.
    func show(_ page: SettingsPage? = nil) {
        let window = self.window ?? makeWindow()
        self.window = window
        if let page { navigation.page = page }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsWindowView(navigation: navigation, state: AppState.shared))
        host.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // A unified toolbar lets the sidebar run up under the title bar and
        // puts the page title beside it, as in System Settings.
        window.toolbar = NSToolbar(identifier: "Settings")
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(SettingsWindowView.idealSize)
        window.center()
        // Reopens where it was left (and at the size it was left); centered
        // the first time.
        window.setFrameAutosaveName("SettingsWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        Self.backToMenuBar(closing: notification.object as? NSWindow)
    }

    /// Hides the Dock icon and app menu again, unless another ThockBox
    /// window (Settings or the welcome window) is still open.
    static func backToMenuBar(closing: NSWindow?) {
        let othersOpen = NSApp.windows.contains {
            $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled)
        }
        if !othersOpen { NSApp.setActivationPolicy(.accessory) }
    }
}

/// Which page the settings window shows; remembered between launches, like
/// other Mac settings windows.
@MainActor
final class SettingsNavigation: ObservableObject {
    nonisolated static let lastPageKey = "settingsLastTab"
    private let defaults: UserDefaults

    @Published var page: SettingsPage {
        didSet {
            if let index = SettingsPage.allCases.firstIndex(of: page) {
                defaults.set(index, forKey: Self.lastPageKey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let last = defaults.integer(forKey: Self.lastPageKey)
        page = SettingsPage.allCases.indices.contains(last) ? SettingsPage.allCases[last] : .sound
    }
}

struct SettingsWindowView: View {
    static let idealSize = NSSize(width: 720, height: 560)

    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { navigation.page }, set: { if let page = $0 { navigation.page = page } })) {
                SettingsSidebarHeader(state: state)
                ForEach(SettingsPage.allCases) { page in
                    SettingsSidebarLabel(page: page)
                        .tag(Optional(page))
                }
            }
            // After hidingSidebarToggle: its `if #available` wrapper hides an
            // earlier column width, leaving the sidebar at 144pt.
            .hidingSidebarToggle()
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            SettingsPageView(page: navigation.page, state: state)
                .id(navigation.page)
                .navigationTitle(navigation.page.title)
        }
        .frame(minWidth: 640, minHeight: 440)
    }
}

/// The app at the top of the sidebar, with what it's doing right now, like
/// the account row at the top of System Settings.
private struct SettingsSidebarHeader: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("ThockBox")
                    .font(.headline)
                Text(state.status.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// A page in the sidebar: a white symbol on a colored rounded square, the
/// way System Settings marks its panes.
struct SettingsSidebarLabel: View {
    let page: SettingsPage

    var body: some View {
        Label {
            Text(page.title)
        } icon: {
            SettingsIcon(symbol: page.sidebarSymbol, color: page.color)
        }
    }
}

struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .accessibilityHidden(true)
    }
}

private extension View {
    /// The sidebar is always shown; there's nothing to hide it for.
    @ViewBuilder func hidingSidebarToggle() -> some View {
        if #available(macOS 14, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

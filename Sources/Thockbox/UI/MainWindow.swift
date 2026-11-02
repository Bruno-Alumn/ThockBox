import AppKit
import SwiftUI

/// The settings window: a standard Mac preferences window with a toolbar
/// tab per page. ThockBox normally lives only in the menu bar (LSUIElement);
/// while this window is open it also shows a Dock icon and app menu, like a
/// regular app, and goes back to menu-bar-only on close.
@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    static let shared = MainWindow()

    private var window: NSWindow?
    private var tabs: NSTabViewController?
    private var tabObservation: NSKeyValueObservation?
    private nonisolated static let lastTabKey = "settingsLastTab"

    /// Brings up the window, on `page` if given.
    func show(_ page: SettingsPage? = nil) {
        let window = self.window ?? makeWindow()
        self.window = window
        if let page, let index = SettingsPage.allCases.firstIndex(of: page) {
            tabs?.selectedTabViewItemIndex = index
        }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for page in SettingsPage.allCases {
            let host = NSHostingController(rootView: SettingsPageView(page: page, state: AppState.shared))
            // Each tab sizes the window to its own content, as standard
            // preferences windows do.
            host.sizingOptions = .preferredContentSize
            host.title = page.title
            let item = NSTabViewItem(viewController: host)
            item.label = page.title
            item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
            tabs.addTabViewItem(item)
        }
        // Opens on the tab used last time, like other Mac settings windows.
        let last = UserDefaults.standard.integer(forKey: Self.lastTabKey)
        if tabs.tabViewItems.indices.contains(last) { tabs.selectedTabViewItemIndex = last }
        tabObservation = tabs.observe(\.selectedTabViewItemIndex) { tabs, _ in
            UserDefaults.standard.set(tabs.selectedTabViewItemIndex, forKey: MainWindow.lastTabKey)
        }
        self.tabs = tabs
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        // Reopens where it was left; centered the first time.
        window.setFrameAutosaveName("Settings")
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

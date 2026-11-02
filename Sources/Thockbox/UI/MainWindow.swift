import AppKit
import SwiftUI

/// The desktop settings window. ThockBox normally lives only in the menu bar
/// (LSUIElement); while this window is open it also shows a Dock icon and
/// app menu, like a regular app, and goes back to menu-bar-only on close.
final class MainWindow: NSObject, NSWindowDelegate {
    static let shared = MainWindow()

    private var window: NSWindow?

    /// Brings up the window, on `page` if given.
    func show(_ page: SettingsPage? = nil) {
        if let page { SettingsNavigation.shared.page = page }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: SettingsView(state: AppState.shared)))
        window.title = "ThockBox"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 720, height: 600))
        window.center()
        // A new name for the sidebar layout, so the old tall, narrow frame
        // isn't restored onto it.
        window.setFrameAutosaveName("ThockBoxSettingsWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

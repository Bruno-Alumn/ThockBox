import AppKit
import SwiftUI

/// The desktop settings window. Thockbox normally lives only in the menu bar
/// (LSUIElement); while this window is open it also shows a Dock icon and
/// app menu, like a regular app, and goes back to menu-bar-only on close.
final class MainWindow: NSObject, NSWindowDelegate {
    static let shared = MainWindow()

    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: SettingsView(state: AppState.shared)))
        window.title = "Thockbox"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 480, height: 720))
        window.center()
        window.setFrameAutosaveName("ThockboxSettings")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

import AppKit
import SwiftUI

/// Shown on first launch until the user clicks Done (or closes it). It covers
/// the two things a menu bar app can't show on its own: that it lives in the
/// menu bar, and that it needs Accessibility access. Granting access
/// relaunches ThockBox, so the window comes back after that until it's done.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindow()

    private nonisolated static let finishedKey = "hasFinishedWelcome"
    private var window: NSWindow?

    /// New installs only: someone who has used Settings before isn't new.
    nonisolated static func isNeeded(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: finishedKey) && !defaults.bool(forKey: "hasShownSettingsWindow")
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: WelcomeView(state: AppState.shared) { [weak self] in
            self?.window?.close()
        })
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "Welcome to ThockBox"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.finishedKey)
        defaults.set(true, forKey: "hasShownSettingsWindow")
        NSApp.setActivationPolicy(.accessory)
    }
}

struct WelcomeView: View {
    @ObservedObject var state: AppState
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text("Welcome to ThockBox")
                    .font(.title2.bold())
                Text("Mechanical keyboard sounds for every key you type.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)

            Form {
                Section {
                    LabeledContent("Keyboard access") {
                        if state.accessibilityTrusted {
                            Label("Allowed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Open System Settings…") { Permissions.openSystemSettings() }
                        }
                    }
                } header: {
                    Text("1. Allow Keyboard Access")
                } footer: {
                    formFooter("macOS needs your permission for ThockBox to hear key presses in other apps. Nothing you type is stored or sent anywhere.")
                }

                Section {
                    SwitchSetPicker(state: state)
                    TryItField()
                } header: {
                    Text("2. Pick a Sound")
                } footer: {
                    formFooter("Change it anytime from the ThockBox icon in the menu bar.")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("ThockBox lives in the menu bar.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
        .onAppear { state.refreshOnOpen() }
    }
}

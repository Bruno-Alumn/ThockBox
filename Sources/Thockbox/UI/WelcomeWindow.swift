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
        // Its full size before centering: SwiftUI sizes the window later,
        // and it would grow down from a spot picked for a smaller one,
        // under the Dock on a short screen.
        window.setContentSize(window.contentViewController?.view.fittingSize ?? window.frame.size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // macOS's Accessibility prompt, after the window: asked any earlier,
        // the window opens over it and hides its buttons. The prompt only
        // comes forward once ThockBox steps back from the front.
        if !Permissions.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                _ = Permissions.requestIfNeeded()
                NSApp.deactivate()
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: WelcomeView(state: AppState.shared) { [weak self] in
            self?.window?.close()
        })
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "Welcome to ThockBox"
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.finishedKey)
        defaults.set(true, forKey: "hasShownSettingsWindow")
        MainWindow.backToMenuBar(closing: notification.object as? NSWindow)
    }
}

struct WelcomeView: View {
    @ObservedObject var state: AppState
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WindowHeader(state: state, title: "Welcome to ThockBox",
                         subtitle: "Mechanical keyboard sounds for every key you type.")

            Form {
                Section {
                    LabeledContent {
                        if state.accessibilityTrusted {
                            Label {
                                Text("Allowed")
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        } else {
                            Button("Open System Settings") { Permissions.openSystemSettings() }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut(.defaultAction)
                        }
                    } label: {
                        Label { Text("Accessibility access") } icon: {
                            SettingsIcon(symbol: "accessibility", color: .blue)
                        }
                    }
                } footer: {
                    formFooter("ThockBox needs this to hear key presses in other apps. Nothing you type leaves your Mac.")
                }

                Section {
                    LabeledContent {
                        SwitchSetPicker(state: state)
                            .labelsHidden()
                    } label: {
                        Label { Text("Switch set") } icon: {
                            SettingsIcon(symbol: SettingsPage.sound.sidebarSymbol, color: SettingsPage.sound.color)
                        }
                    }
                    LabeledContent {
                        TryItField()
                            .labelsHidden()
                    } label: {
                        Label { Text("Try it") } icon: {
                            SettingsIcon(symbol: SettingsPage.keys.sidebarSymbol, color: SettingsPage.keys.color)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("ThockBox lives in the menu bar.")
                    .foregroundStyle(.secondary)
                Spacer()
                // Until access is allowed, Return opens System Settings instead.
                if state.accessibilityTrusted {
                    Button("Done", action: done)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done", action: done)
                }
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
        .onAppear { state.refreshOnOpen() }
    }
}

/// The top of the Welcome and What's New windows: the app icon (pressable
/// like a key) over a title and a line under it, centered, as in Apple's
/// own first-run and what's-new screens.
struct WindowHeader: View {
    @ObservedObject var state: AppState
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            TappableAppIcon(state: state)
            VStack(spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 24)
        .padding(.horizontal, 20)
    }
}

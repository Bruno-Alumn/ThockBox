import SwiftUI

/// The menu bar menu: a standard macOS menu. What ThockBox is doing comes
/// first, then the things people change day to day. Everything else is in
/// Settings.
struct MenuView: View {
    @ObservedObject var state: AppState
    @ObservedObject var updater = Updater.shared

    /// Volume steps offered in the menu; Settings has the full slider.
    static let volumeSteps = Array(stride(from: 10, through: 100, by: 10))

    var body: some View {
        let status = state.status
        Text(status.title)
        if status == .needsAccess {
            Button("Open Accessibility Settings…") { Permissions.openSystemSettings() }
        }
        if case .blocked = status {
            Button("Why Is Sound Paused?") { explain(status) }
        }
        Divider()

        Toggle("Sounds On", isOn: $state.enabled)
        if state.enabled {
            Button("Turn Off for an Hour") { state.turnOff(for: 3600) }
        }
        Picker("Switch", selection: Binding(
            get: { state.currentPack?.id ?? "" },
            set: { state.selectedPackID = $0 }
        )) {
            ForEach(state.packs) { pack in
                Text(pack.name).tag(pack.id)
            }
        }
        .disabled(!state.enabled)
        Picker("Volume", selection: Binding(
            get: { Int((state.volume * 10).rounded()) * 10 },
            set: { state.volume = Float($0) / 100 }
        )) {
            ForEach(Self.volumeSteps, id: \.self) { step in
                Text("\(step)%").tag(step)
            }
        }
        .disabled(!state.enabled)
        if let app = state.frontApp {
            Toggle("Mute in \(app.name)", isOn: Binding(
                get: { state.mutedApps.contains(app.id) },
                set: { state.setMuted($0, appID: app.id) }))
        }
        Divider()

        if let release = updater.availableRelease {
            Button("Update to \(release.version)…") { MainWindow.shared.show(.general) }
        }
        Button("Settings…") { MainWindow.shared.show() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit ThockBox") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// The full explanation in a standard alert; a menu item can't hold it.
    private func explain(_ status: PlaybackStatus) {
        let alert = NSAlert()
        alert.messageText = status.title
        alert.informativeText = status.detail ?? ""
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

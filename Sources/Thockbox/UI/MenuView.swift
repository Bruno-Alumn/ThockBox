import SwiftUI

/// The menu bar menu: a standard macOS menu. What ThockBox is doing comes
/// first, then the things people change day to day. Everything else is in
/// Settings.
struct MenuView: View {
    @ObservedObject var state: AppState
    @ObservedObject var updater = Updater.shared

    var body: some View {
        let status = state.status
        Text(status.title)
        if status == .needsAccess {
            Button("Open Accessibility Settings…") { Permissions.openSystemSettings() }
        }
        if case .blocked = status {
            Button("Why Is Sound Paused?") { explain(status) }
        }
        if case .muted(let reason) = status, reason != .idle {
            Button("Play Anyway") { state.playAnyway() }
        }
        Divider()

        Toggle("Sounds On", isOn: $state.enabled)
        if state.enabled {
            Menu("Turn Off For") {
                Button("15 Minutes") { state.turnOff(for: 15 * 60) }
                Button("1 Hour") { state.turnOff(for: 3600) }
                Button("4 Hours") { state.turnOff(for: 4 * 3600) }
                Button("Until Tomorrow Morning") { state.turnOff(for: AppState.untilMorning()) }
            }
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
        // The slider itself is an AppKit item added under this heading when
        // the menu opens; see MenuVolumeItem.
        Text(MenuVolumeItem.heading)
        if let app = state.frontApp {
            if state.playOnlyInListedApps {
                Toggle("Play in \(app.name)", isOn: Binding(
                    get: { state.mutedApps.contains(app.id) },
                    set: { state.setMuted($0, appID: app.id) }))
            } else {
                Toggle("Mute in \(app.name)", isOn: Binding(
                    get: { state.mutedApps.contains(app.id) },
                    set: { state.setMuted($0, appID: app.id) }))
            }
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

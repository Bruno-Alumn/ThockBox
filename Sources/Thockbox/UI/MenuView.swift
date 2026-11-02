import SwiftUI

/// The menu bar panel: what ThockBox is doing, and the few things people
/// change from day to day. Everything else is in the settings window.
struct MenuView: View {
    @ObservedObject var state: AppState
    @ObservedObject var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(14)
            Divider()
            sound
                .padding(14)
            if let app = state.frontApp {
                Divider()
                muteInApp(app)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            if let release = updater.availableRelease {
                Divider()
                updateRow(release)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            Divider()
            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 300)
        .tint(.thockCoral)
        .onAppear { state.refreshAccessibilityStatus() }
    }

    /// Name, status and the switch that turns everything on or off.
    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("ThockBox")
                    .font(.headline)
                StatusView(state: state)
            }
            Spacer(minLength: 8)
            Toggle("Sounds", isOn: $state.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Turn sounds on or off (\(state.toggleShortcut.display))")
        }
    }

    private var sound: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
            GridRow {
                Text("Switch")
                    .foregroundStyle(.secondary)
                SwitchPicker(state: state)
                    .labelsHidden()
            }
            GridRow {
                Text("Volume")
                    .foregroundStyle(.secondary)
                VolumeSlider(state: state)
            }
        }
        .disabled(!state.enabled)
    }

    /// The app you came from, one switch away from being muted.
    private func muteInApp(_ app: FrontApp) -> some View {
        HStack(spacing: 8) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text("Mute in \(app.name)")
            Spacer()
            Toggle("Mute in \(app.name)", isOn: Binding(
                get: { state.mutedApps.contains(app.id) },
                set: { state.setMuted($0, appID: app.id) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    private func updateRow(_ release: Release) -> some View {
        Button {
            MainWindow.shared.show(.general)
        } label: {
            Label("Update to \(release.version)…", systemImage: "arrow.down.circle.fill")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.thockCoral)
    }

    private var footer: some View {
        HStack {
            KeysTodayText(store: state.stats)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Settings…") { MainWindow.shared.show() }
                .keyboardShortcut(",")
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .controlSize(.small)
    }
}

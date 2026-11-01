import SwiftUI

/// The menu bar panel: quick settings only. Everything else lives in the
/// settings window (SettingsView), opened with "Settings…".
struct MenuView: View {
    @ObservedObject var state: AppState
    @ObservedObject var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !state.accessibilityTrusted {
                PermissionBanner()
            }
            if let app = state.secureInputApp {
                SecureInputBanner(app: app)
            }
            if state.enabled, let mute = state.automaticMute {
                Label(mute.message, systemImage: mute.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let release = updater.availableRelease {
                UpdateBanner(release: release)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    sectionTitle("Switches")
                    Spacer()
                    PreviewButton(state: state)
                        .controlSize(.mini)
                        .buttonStyle(.borderless)
                }
                SwitchList(state: state)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Volume")
                VolumeControl(state: state)
            }
            if let app = state.frontApp {
                HStack {
                    Text("Mute in \(app.name)")
                        .font(.caption)
                    Spacer()
                    Toggle("Mute in \(app.name)", isOn: Binding(
                        get: { state.mutedApps.contains(app.id) },
                        set: { state.setMuted($0, appID: app.id) }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 280)
        .tint(.thockCoral)
        .onAppear { state.refreshAccessibilityStatus() }
    }

    private var header: some View {
        HStack {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 20, height: 20)
            Text("ThockBox")
                .font(.headline)
            Spacer()
            Toggle("", isOn: $state.enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Toggle sounds (\(state.toggleShortcut.display))")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatsLine(store: state.stats)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Button("Settings…") { MainWindow.shared.show() }
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
    }
}

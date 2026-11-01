import SwiftUI

/// The menu bar panel: quick settings only. Everything else lives in the
/// settings window (SettingsView), opened with "Settings…".
struct MenuView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !state.accessibilityTrusted {
                PermissionBanner()
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
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { state.refreshAccessibilityStatus() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "keyboard.fill")
                .foregroundStyle(.secondary)
            Text("Thockbox")
                .font(.headline)
            Spacer()
            Toggle("", isOn: $state.enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Toggle sounds (⌘⌃K)")
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

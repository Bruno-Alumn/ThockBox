import SwiftUI

/// Controls shown both in the menu bar panel and the settings window.

struct PermissionBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accessibility permission needed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)
            Text("ThockBox needs Accessibility access to hear your keystrokes. No keystroke data ever leaves your Mac.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") { Permissions.openSystemSettings() }
                .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.orange.opacity(0.1)))
    }
}

struct SwitchList: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(state.packs) { pack in
                Button {
                    state.selectedPackID = pack.id
                } label: {
                    HStack {
                        Image(systemName: state.currentPack?.id == pack.id
                              ? "circle.inset.filled" : "circle")
                            .foregroundStyle(state.currentPack?.id == pack.id
                                             ? Color.thockCoral : Color.secondary)
                        Text(pack.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct PreviewButton: View {
    @ObservedObject var state: AppState

    var body: some View {
        Button("Preview") { state.playSwitchPreview() }
            .disabled(!state.enabled || state.isAutomaticallyMuted || state.packs.isEmpty)
    }
}

struct VolumeControl: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "speaker.fill").imageScale(.small)
                Slider(value: $state.volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill").imageScale(.small)
            }
            HStack {
                ForEach(VolumePreset.allCases, id: \.self) { preset in
                    Button(preset.label) { state.volume = preset.value }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .tint(abs(state.volume - preset.value) < 0.01 ? .thockCoral : nil)
                }
            }
        }
    }
}

struct OutputDevicePicker: View {
    @ObservedObject var state: AppState
    // Cached: enumerating CoreAudio devices inside body is slow, and body
    // re-runs on every AppState change.
    @State private var devices: [AudioDevices.Device] = []
    @State private var deviceMonitor: AudioDeviceMonitor?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Play through", selection: Binding(
                get: { state.outputDeviceUID ?? "" },
                set: { state.outputDeviceUID = $0.isEmpty ? nil : $0 }
            )) {
                Text("System Default").tag("")
                ForEach(devices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            // Bluetooth headphones buffer ~100–250 ms on their own; say so,
            // since it reads as the app lagging.
            let latencyMs = Int((state.engine.outputLatency * 1000).rounded())
            if latencyMs >= 40 {
                Text("This output delays sound by ~\(latencyMs) ms (typical for Bluetooth). Speakers or wired headphones respond instantly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            devices = AudioDevices.outputDevices()
            deviceMonitor = AudioDeviceMonitor {
                DispatchQueue.main.async { devices = AudioDevices.outputDevices() }
            }
        }
        .onDisappear { deviceMonitor = nil }
    }
}

/// Watches only the keystroke counts, so typing doesn't re-render the rest.
struct StatsLine: View {
    @ObservedObject var store: StatsStore

    var body: some View {
        Text("\(store.shown.today.formatted()) today · \(store.shown.total.formatted()) total")
    }
}

enum VolumePreset: CaseIterable {
    case soft, balanced, loud

    var label: String {
        switch self {
        case .soft: "Soft"
        case .balanced: "Balanced"
        case .loud: "Loud"
        }
    }

    var value: Float {
        switch self {
        case .soft: 0.25
        case .balanced: 0.55
        case .loud: 0.9
        }
    }
}

/// The menu bar panel's notice that a newer release is out. Opens the
/// settings window, where the update is installed.
struct UpdateBanner: View {
    let release: Release

    var body: some View {
        Button {
            MainWindow.shared.show()
        } label: {
            Label("ThockBox \(release.version) is available", systemImage: "arrow.down.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(Color.thockCoral)
        }
        .buttonStyle(.borderless)
        .help("Open Settings to install the update")
    }
}

/// The settings window's update row: current version, check status, and
/// the button that matches it.
struct UpdateStatusView: View {
    @ObservedObject var updater: Updater

    var body: some View {
        LabeledContent {
            controls
        } label: {
            Text("Version \(AppVersion.current)")
            Text(statusText)
        }
    }

    private var statusText: String {
        switch updater.status {
        case .idle: "Checks GitHub for new releases."
        case .checking: "Checking…"
        case .upToDate: "You're up to date."
        case .available(let release): "Version \(release.version) is available."
        case .downloading: "Downloading…"
        case .installing: "Installing…"
        case .failed(let message), .installFailed(_, let message): message
        }
    }

    @ViewBuilder private var controls: some View {
        switch updater.status {
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        case .available(let release):
            HStack {
                Button("Release Notes") { NSWorkspace.shared.open(release.pageURL) }
                Button("Install and Relaunch") { Task { await updater.install(release) } }
                    .buttonStyle(.borderedProminent)
            }
        case .installFailed(let release, _):
            HStack {
                Button("Try Again") { Task { await updater.install(release) } }
                Button("Download from GitHub") { NSWorkspace.shared.open(release.pageURL) }
                    .buttonStyle(.borderedProminent)
            }
        default:
            Button("Check Now") { Task { await updater.check(userInitiated: true) } }
        }
    }
}

/// The apps ThockBox stays quiet in, with Add and Remove.
struct MutedAppsList: View {
    @ObservedObject var state: AppState

    var body: some View {
        ForEach(state.mutedApps, id: \.self) { id in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            HStack {
                if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 18, height: 18)
                }
                Text(url.map { $0.deletingPathExtension().lastPathComponent } ?? id)
                Spacer()
                Button {
                    state.mutedApps.removeAll { $0 == id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove")
            }
        }
        Button("Add App…", action: chooseApps)
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Mute"
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        state.mutedApps += ids.filter { !state.mutedApps.contains($0) }
    }
}

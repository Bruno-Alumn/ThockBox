import SwiftUI

/// Pieces used by both the menu bar panel and the settings window.

/// The status line: what ThockBox is doing and, when something needs fixing,
/// why and the button that fixes it.
struct StatusView: View {
    @ObservedObject var state: AppState
    /// The settings sidebar is narrow, so it leaves the explanation for
    /// problems only; the menu bar panel explains every state.
    var showsDetailOnlyForProblems = false

    var body: some View {
        let status = state.status
        VStack(alignment: .leading, spacing: 6) {
            Label(status.title, systemImage: status.symbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(status.needsAttention ? Color.orange : Color.secondary)
                .labelStyle(StatusLabelStyle(tint: status.needsAttention ? .orange : symbolTint(status)))
            if let detail = status.detail, status.needsAttention || !showsDetailOnlyForProblems {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if status == .needsAccess {
                Button("Open System Settings") { Permissions.openSystemSettings() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func symbolTint(_ status: PlaybackStatus) -> Color {
        if case .playing = status { return .thockCoral }
        return .secondary
    }
}

private struct StatusLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .foregroundStyle(tint)
                .frame(width: 16)
            configuration.title
        }
    }
}

/// Switch sets as a pop-up menu: one line in the menu bar panel no matter
/// how many sets there are. Choosing one plays a sample of it.
struct SwitchPicker: View {
    @ObservedObject var state: AppState

    var body: some View {
        Picker("Switch", selection: Binding(
            get: { state.currentPack?.id ?? "" },
            set: { state.selectedPackID = $0 }
        )) {
            ForEach(state.packs) { pack in
                Text(pack.name).tag(pack.id)
            }
        }
        .pickerStyle(.menu)
    }
}

/// All switch sets as a list, for the settings window. Choosing one plays a
/// sample of it; sets the user added can be removed.
struct SwitchList: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(state.packs) { pack in
                let selected = state.currentPack?.id == pack.id
                HStack {
                    Button {
                        state.selectedPackID = pack.id
                    } label: {
                        HStack {
                            Image(systemName: selected ? "circle.inset.filled" : "circle")
                                .foregroundStyle(selected ? Color.thockCoral : Color.secondary)
                            Text(pack.name)
                            if UserPacks.isUserPack(pack) {
                                Text("Yours")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    if UserPacks.isUserPack(pack) {
                        Button {
                            remove(pack)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove \(pack.name) (moves its files to the Trash)")
                        .accessibilityLabel("Remove \(pack.name)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func remove(_ pack: SoundPack) {
        do {
            try state.removeSwitchSet(pack)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

struct VolumeSlider: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            // labelsHidden: in a grouped Form an unlabeled slider would sit
            // in the value column, at half width.
            Slider(value: $state.volume, in: 0...1)
                .labelsHidden()
                .accessibilityLabel("Volume")
            Image(systemName: "speaker.wave.3.fill")
                .imageScale(.small)
                .foregroundStyle(.secondary)
        }
    }
}

/// The Tone Pad with its directions written on its edges, so it explains
/// itself, and the pitch variation slider under it.
struct ToneControl: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(spacing: 4) {
                edgeLabel("Higher")
                HStack(spacing: 6) {
                    edgeLabel("Darker")
                    TonePadView(x: $state.toneX, y: $state.toneY)
                        .frame(width: 132, height: 132)
                    edgeLabel("Brighter")
                }
                edgeLabel("Lower")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Variation")
                HStack(spacing: 6) {
                    Text("None")
                    Slider(value: $state.pitchVariation, in: 0...150)
                        .labelsHidden()
                        .accessibilityLabel("Pitch variation")
                    Text("More")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Text("Varies the pitch of each key a little, like a real keyboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func edgeLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize()
            .accessibilityHidden(true)
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
struct KeysTodayText: View {
    @ObservedObject var store: StatsStore

    var body: some View {
        Text("\(store.shown.today.formatted()) keys today")
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
                    state.setMuted(false, appID: id)
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
        panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            .forEach { state.setMuted(true, appID: $0) }
    }
}

/// Click, then press the new shortcut. Esc cancels.
struct ShortcutRecorder: View {
    @ObservedObject var state: AppState
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(monitor == nil ? state.toggleShortcut.display : "Press keys…") {
                monitor == nil ? start() : stop()
            }
            .frame(minWidth: 90)
            if monitor == nil && state.toggleShortcut != .standard {
                Button("Reset") { state.toggleShortcut = .standard }
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        state.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
            } else if let shortcut = Shortcut(event: event) {
                state.toggleShortcut = shortcut
                stop()
            } else {
                NSSound.beep() // needs ⌘, ⌃ or ⌥
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        state.isRecordingShortcut = false
    }
}

import SwiftUI

/// Controls used in the settings window that SwiftUI doesn't provide as is.

/// Section footer text in the standard footnote style, leading-aligned as
/// in System Settings. A Form sized to its content (as each settings tab
/// is) drops the default footer styling and alignment, so it's set here.
func formFooter(_ text: String) -> some View {
    Text(text)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
}

/// The switch set pop-up. Choosing one plays a sample of it.
struct SwitchSetPicker: View {
    @ObservedObject var state: AppState

    var body: some View {
        Picker("Switch set", selection: Binding(
            get: { state.currentPack?.id ?? "" },
            set: { state.selectedPackID = $0 }
        )) {
            ForEach(state.packs) { pack in
                Text(pack.name).tag(pack.id)
            }
        }
    }
}

/// A text field to type in and hear the current switch set. Keys typed in
/// ThockBox's own windows play without Accessibility access, so this works
/// before access is granted. What's typed isn't kept.
struct TryItField: View {
    @State private var text = ""

    var body: some View {
        TextField("Try it", text: $text, prompt: Text("Type here to hear it"))
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

/// The apps ThockBox stays quiet in: a standard list with + and − below.
struct MutedAppsList: View {
    @ObservedObject var state: AppState
    @State private var selection: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            List(state.mutedApps, id: \.self, selection: $selection) { id in
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                Label {
                    Text(url.map(Self.appName) ?? id)
                } icon: {
                    if let url {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 110)
            .onDeleteCommand(perform: removeSelection)
            .overlay {
                if state.mutedApps.isEmpty {
                    Text("No apps").foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                Button(action: chooseApps) { Image(systemName: "plus") }
                    .help("Add apps")
                    .accessibilityLabel("Add Apps")
                Button(action: removeSelection) {
                    Image(systemName: "minus")
                }
                .disabled(selection.isEmpty)
                .help("Remove the selected apps")
                .accessibilityLabel("Remove Selected Apps")
            }
            .buttonStyle(.borderless)
        }
    }

    /// The app's own name in the user's language: "Safari", never
    /// "Safari.app", even with file extensions shown in Finder.
    static func appName(_ url: URL) -> String {
        let bundle = Bundle(url: url)
        let info = bundle?.localizedInfoDictionary ?? [:]
        let fallback = bundle?.infoDictionary ?? [:]
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = (info[key] ?? fallback[key]) as? String, !name.isEmpty { return name }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func removeSelection() {
        selection.forEach { state.setMuted(false, appID: $0) }
        selection = []
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
            .accessibilityLabel(monitor == nil ? "Shortcut" : "Recording shortcut")
            .accessibilityValue(monitor == nil ? state.toggleShortcut.spoken : "Press the new keys")
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

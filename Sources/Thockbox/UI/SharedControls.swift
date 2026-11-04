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
        // Grouped form footers stop at a few lines otherwise, ending in "…".
        .fixedSize(horizontal: false, vertical: true)
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

/// The app icon, pressable like a key: it sinks and plays the current set's
/// space bar on press and release. A small thing for idle clicks.
struct TappableAppIcon: View {
    @ObservedObject var state: AppState
    var size: CGFloat = 64
    @State private var pressed = false

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
            .scaleEffect(pressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    state.pressAppIcon(down: true)
                }
                .onEnded { _ in
                    pressed = false
                    state.pressAppIcon(down: false)
                })
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
        Picker(selection: Binding(
            get: { state.outputDeviceUID ?? "" },
            set: { state.outputDeviceUID = $0.isEmpty ? nil : $0 }
        )) {
            Text("System Default").tag("")
            ForEach(devices) { device in
                Text(device.name).tag(device.uid)
            }
            // The picked device stays listed while it's unplugged; sound
            // goes to the default until it's back.
            if let uid = state.outputDeviceUID, !devices.contains(where: { $0.uid == uid }) {
                Text("\(state.outputDeviceName ?? "Unknown Device") (Not Connected)").tag(uid)
            }
        } label: {
            Text("Play through")
            if latencyMs >= 40 {
                Text("Delays sound by about \(latencyMs) ms, typical for Bluetooth.")
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

    // Bluetooth headphones buffer ~100–250 ms on their own; say so,
    // since it reads as the app lagging.
    private var latencyMs: Int { Int((state.engine.outputLatency * 1000).rounded()) }
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
                    Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .applicationBundle))
                        .resizable()
                        .frame(width: 16, height: 16)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 110)
            .onDeleteCommand(perform: removeSelection)
            .overlay {
                if state.mutedApps.isEmpty {
                    Text("No Apps").foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                Button(action: chooseApps) {
                    Image(systemName: "plus").frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .help("Add apps")
                .accessibilityLabel("Add Apps")
                Button(action: removeSelection) {
                    Image(systemName: "minus").frame(width: 20, height: 20).contentShape(Rectangle())
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
        panel.prompt = state.playOnlyInListedApps ? "Add" : "Mute"
        guard panel.runModal() == .OK else { return }
        panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            .forEach { state.setMuted(true, appID: $0) }
    }
}

/// Click, then press the new shortcut. Esc cancels.
struct ShortcutRecorder: View {
    @ObservedObject var state: AppState
    /// Set when a combination was refused, so the page can say what works.
    @Binding var rejected: Bool
    /// Which shortcut this records; the on/off one unless given.
    var shortcut: Binding<Shortcut?>? = nil
    /// What Reset goes back to; nil means the shortcut can be cleared.
    var standard: Shortcut? = .standard
    /// What VoiceOver calls this recorder; matches its row title.
    var title: String = "Turn sounds on or off"
    @State private var monitor: Any?

    private var value: Binding<Shortcut?> {
        shortcut ?? Binding(get: { state.toggleShortcut }, set: { if let new = $0 { state.toggleShortcut = new } })
    }

    var body: some View {
        HStack(spacing: 6) {
            // Before the recorder, so every recorder on the page stays in one
            // column whether or not it has something to clear.
            if monitor == nil && value.wrappedValue != standard {
                Button {
                    value.wrappedValue = standard
                } label: {
                    Image(systemName: standard == nil ? "xmark.circle.fill" : "arrow.counterclockwise.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(standard == nil ? "Clear" : "Reset to \(standard?.display ?? "")")
                .accessibilityLabel(standard == nil ? "Clear Shortcut for \(title)" : "Reset Shortcut for \(title)")
            }
            Button {
                monitor == nil ? start() : stop()
            } label: {
                Text(monitor == nil ? (value.wrappedValue?.display ?? "None") : "Press keys…")
                    .frame(minWidth: 76)
            }
            .accessibilityLabel(monitor == nil ? title : "Recording \(title)")
            .accessibilityValue(monitor == nil ? (value.wrappedValue?.spoken ?? "None") : "Press the new keys")
        }
        .onDisappear(perform: stop)
        // Recording turns the shortcut off; don't leave it off while the
        // user is in another app, where key presses never reach the recorder.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stop()
        }
    }

    private func start() {
        rejected = false
        state.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
            } else if let recorded = Shortcut(event: event), !takenByTheOther(recorded) {
                value.wrappedValue = recorded
                stop()
            } else if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                // A real attempt that would clash: say what works.
                NSSound.beep()
                rejected = true
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    /// Two shortcuts can't be the same keys.
    private func takenByTheOther(_ recorded: Shortcut) -> Bool {
        recorded != value.wrappedValue && state.allShortcuts.contains(recorded)
    }

    private func stop() {
        guard let monitor else { return } // not recording
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        state.isRecordingShortcut = false
    }
}

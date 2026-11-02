import SwiftUI

/// The settings window: a sidebar with the master switch, the current status
/// and five pages, each about one thing.
struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var navigation = SettingsNavigation.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
            Divider()
            page
                .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, minHeight: 520)
        .tint(.thockCoral)
        .onAppear { state.refreshAccessibilityStatus() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 36, height: 36)
                Text("ThockBox")
                    .font(.headline)
                Spacer()
                Toggle("Sounds", isOn: $state.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .help("Turn sounds on or off (\(state.toggleShortcut.display))")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)
            StatusView(state: state, showsDetailOnlyForProblems: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            Divider()
                .padding(.horizontal, 14)
            VStack(spacing: 2) {
                ForEach(SettingsPage.allCases) { page in
                    sidebarRow(page)
                }
            }
            .padding(8)
            Spacer()
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
    }

    private func sidebarRow(_ page: SettingsPage) -> some View {
        let selected = navigation.page == page
        return Button {
            navigation.page = page
        } label: {
            Label(page.title, systemImage: page.symbol)
                .labelStyle(SidebarLabelStyle(selected: selected))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.thockCoral.opacity(0.18) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var page: some View {
        switch navigation.page {
        case .sound: SoundPage(state: state)
        case .keys: KeysPage(state: state)
        case .muting: MutingPage(state: state)
        case .activity: ActivityPage(store: state.stats)
        case .general: GeneralPage(state: state)
        }
    }
}

private struct SidebarLabelStyle: LabelStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .foregroundStyle(selected ? Color.thockCoral : Color.secondary)
                .frame(width: 20)
            configuration.title
                .fontWeight(selected ? .medium : .regular)
        }
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case sound, keys, muting, activity, general

    var id: Self { self }

    var title: String {
        switch self {
        case .sound: "Sound"
        case .keys: "Keys"
        case .muting: "Muting"
        case .activity: "Activity"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .sound: "speaker.wave.2"
        case .keys: "keyboard"
        case .muting: "speaker.slash"
        case .activity: "chart.bar"
        case .general: "gearshape"
        }
    }
}

/// Which page the settings window shows; the menu bar panel can open it on
/// a specific one (e.g. General, for an update).
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var page: SettingsPage = .sound
}

/// A page title over a grouped form.
private struct SettingsPageLayout<Content: View>: View {
    let page: SettingsPage
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.title)
                .font(.title2.bold())
                .padding(.horizontal, 20)
                .padding(.top, 18)
            Form { content }
                .formStyle(.grouped)
        }
    }
}

// MARK: - Sound

/// How it sounds: which switches, how loud, what tone, through what.
private struct SoundPage: View {
    @ObservedObject var state: AppState
    @State private var isDropTarget = false

    var body: some View {
        SettingsPageLayout(page: .sound) {
            Section {
                SwitchList(state: state)
                    // Dropping a folder of recordings here adds it, like the button.
                    .dropDestination(for: URL.self) { urls, _ in
                        importSwitchSet(from: urls)
                        return true
                    } isTargeted: { isDropTarget = $0 }
                    .overlay {
                        if isDropTarget {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.thockCoral, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                .padding(-4)
                        }
                    }
                Button("Add Your Own…", action: addSwitchSet)
            } header: {
                Text("Switch")
            } footer: {
                Text("Choose a set to hear it. To use your own recordings, add a folder of them or drop it on the list. Name files with space, enter or backspace to give those keys their own sound, and with up or release for the sound of a key being let go.")
            }

            Section {
                VolumeSlider(state: state)
            } header: {
                Text("Volume")
            } footer: {
                Text("Each output device keeps its own volume, so headphones and speakers can differ.")
            }

            Section {
                ToneControl(state: state)
            } header: {
                HStack {
                    Text("Tone")
                    Spacer()
                    Button("Reset") {
                        state.toneX = 0
                        state.toneY = 0
                        state.pitchVariation = 60
                    }
                    .controlSize(.small)
                    .disabled(state.toneX == 0 && state.toneY == 0 && state.pitchVariation == 60)
                }
            }

            Section("Output") {
                OutputDevicePicker(state: state)
            }
        }
    }

    private func addSwitchSet() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.audio, .folder]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose a folder of key recordings, or the files themselves."
        guard panel.runModal() == .OK else { return }
        importSwitchSet(from: panel.urls)
    }

    private func importSwitchSet(from urls: [URL]) {
        do {
            try state.importSwitchSet(from: urls)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

// MARK: - Keys

/// What makes a sound, and the shortcut that turns it all off.
private struct KeysPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        SettingsPageLayout(page: .keys) {
            Section("Shortcut") {
                LabeledContent("Turn sounds on or off") {
                    ShortcutRecorder(state: state)
                }
            }

            Section {
                Toggle("Modifier keys (⌘ ⌥ ⌃ ⇧)", isOn: Binding(
                    get: { !state.muteModifiers },
                    set: { state.muteModifiers = !$0 }))
                Toggle("Function keys", isOn: $state.functionKeysAudible)
                Toggle("Mouse clicks", isOn: $state.mouseClicks)
            } header: {
                Text("Also play sounds for")
            } footer: {
                Text("Letters, numbers, Space, Return and the other typing keys always play.")
            }

            Section {
                Toggle("Typewriter ding on Return", isOn: $state.returnDing)
                Toggle("Trackpad tap with each key", isOn: $state.hapticFeedback)
            } header: {
                Text("Extras")
            } footer: {
                Text("The trackpad tap needs a Force Touch trackpad.")
            }
        }
    }
}

// MARK: - Muting

/// When ThockBox goes quiet by itself.
private struct MutingPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        SettingsPageLayout(page: .muting) {
            Section {
                if MicrophoneMonitor.isSupported {
                    Toggle("During calls and recordings", isOn: $state.muteDuringCalls)
                }
                Toggle("While the screen is locked", isOn: $state.muteWhenLocked)
                Picker("After no typing for", selection: $state.idleTimeoutMinutes) {
                    Text("Never").tag(0)
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                }
            } header: {
                Text("Mute automatically")
            } footer: {
                if MicrophoneMonitor.isSupported {
                    Text("Calls and recordings means any app using the microphone. \"Hey Siri\" doesn't count.")
                }
            }

            Section {
                MutedAppsList(state: state)
            } header: {
                Text("Mute in these apps")
            } footer: {
                Text("ThockBox stays quiet while one of these apps is in front. The menu bar panel can also mute the app you're in.")
            }
        }
    }
}

// MARK: - Activity

private struct ActivityPage: View {
    @ObservedObject var store: StatsStore

    var body: some View {
        SettingsPageLayout(page: .activity) {
            Section {
                HStack(spacing: 0) {
                    tile("Today", store.shown.today)
                    Divider()
                    tile("All time", store.shown.total)
                }
                .frame(height: 64)
            }

            Section("Last 7 days") {
                if store.shown.lastWeek().allSatisfy({ $0.count == 0 }) {
                    Text("Nothing yet. Start typing and this fills in day by day.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    KeystrokeChart(store: store)
                }
            }
        }
    }

    private func tile(_ title: String, _ count: Int) -> some View {
        VStack(spacing: 2) {
            Text(count.formatted())
                .font(.title.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - General

private struct GeneralPage: View {
    @ObservedObject var state: AppState
    @ObservedObject var updater = Updater.shared

    var body: some View {
        SettingsPageLayout(page: .general) {
            Section {
                Toggle("Open at login", isOn: $state.launchAtLogin)
                Toggle(isOn: $state.showMenuBarIcon) {
                    Text("Show in menu bar")
                    if !state.showMenuBarIcon {
                        Text("Open ThockBox from Applications or Spotlight to get back here.")
                    }
                }
            }

            Section {
                Toggle("Check automatically", isOn: $updater.checksAutomatically)
                UpdateStatusView(updater: updater)
                if let notes = updater.availableRelease?.notesPreview {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text("Updates")
            } footer: {
                if updater.availableRelease != nil && Updater.isAdHocSigned {
                    Text("After updating, macOS may ask you to allow Accessibility access again.")
                }
            }

            Section("Help") {
                LabeledContent("Accessibility access") {
                    if state.accessibilityTrusted {
                        Text("Allowed").foregroundStyle(.secondary)
                    } else {
                        Button("Open System Settings") { Permissions.openSystemSettings() }
                    }
                }
                Link("Troubleshooting", destination: URL(string: "https://github.com/Bruno-Alumn/ThockBox#troubleshooting")!)
            }
        }
    }
}

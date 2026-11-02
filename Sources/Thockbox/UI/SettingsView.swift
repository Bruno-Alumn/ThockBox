import SwiftUI

/// The settings window's pages, one per toolbar tab (see MainWindow). Each is
/// a grouped Form of standard controls.
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

struct SettingsPageView: View {
    let page: SettingsPage
    @ObservedObject var state: AppState

    var body: some View {
        Group {
            switch page {
            case .sound: SoundPage(state: state)
            case .keys: KeysPage(state: state)
            case .muting: MutingPage(state: state)
            case .activity: ActivityPage(store: state.stats)
            case .general: GeneralPage(state: state)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { state.refreshAccessibilityStatus() }
    }
}

/// Section footer text in the standard footnote style, leading-aligned as
/// in System Settings. A Form sized to its content (as each tab is) drops
/// the default footer styling and alignment, so it's set explicitly.
private func footer(_ text: String) -> some View {
    Text(text)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
}

/// Shown at the top of a page only when something needs fixing.
private struct AttentionSection: View {
    @ObservedObject var state: AppState

    var body: some View {
        let status = state.status
        if status.needsAttention {
            Section {
                Label {
                    Text(status.title)
                    if let detail = status.detail { Text(detail) }
                } icon: {
                    Image(systemName: status.symbol)
                        .foregroundStyle(.orange)
                }
                if status == .needsAccess {
                    Button("Open Accessibility Settings…") { Permissions.openSystemSettings() }
                }
            }
        }
    }
}

// MARK: - Sound

private struct SoundPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            AttentionSection(state: state)

            Section {
                Toggle("Play keyboard sounds", isOn: $state.enabled)
            } footer: {
                footer("Turn sounds on or off anytime with \(state.toggleShortcut.display).")
            }

            Section {
                Picker("Switch set", selection: Binding(
                    get: { state.currentPack?.id ?? "" },
                    set: { state.selectedPackID = $0 }
                )) {
                    ForEach(state.packs) { pack in
                        Text(pack.name).tag(pack.id)
                    }
                }
                HStack {
                    Button("Add Your Own…", action: addSwitchSet)
                    let added = state.packs.filter { UserPacks.isUserPack($0) }
                    if !added.isEmpty {
                        Menu("Remove") {
                            ForEach(added) { pack in
                                Button(pack.name) { remove(pack) }
                            }
                        }
                        .fixedSize()
                    }
                }
            } footer: {
                footer("Choosing a set plays a sample of it. Add a Mechvibes sound pack or a folder of your own recordings, or drop one on this window.")
            }

            Section {
                Slider(value: $state.volume, in: 0...1) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill")
                }
                OutputDevicePicker(state: state)
            } footer: {
                footer("Each output device keeps its own volume.")
            }

            Section {
                Slider(value: $state.toneX, in: -1...1) {
                    Text("Brightness")
                } minimumValueLabel: {
                    Text("Darker")
                } maximumValueLabel: {
                    Text("Brighter")
                }
                Slider(value: $state.toneY, in: -1...1) {
                    Text("Pitch")
                } minimumValueLabel: {
                    Text("Lower")
                } maximumValueLabel: {
                    Text("Higher")
                }
                Slider(value: $state.pitchVariation, in: 0...150) {
                    Text("Variation")
                } minimumValueLabel: {
                    Text("None")
                } maximumValueLabel: {
                    Text("More")
                }
                Button("Reset Tone") {
                    state.toneX = 0
                    state.toneY = 0
                    state.pitchVariation = 60
                }
                .disabled(state.toneX == 0 && state.toneY == 0 && state.pitchVariation == 60)
            } header: {
                Text("Tone")
            } footer: {
                footer("Variation changes the pitch of each key a little, like a real keyboard.")
            }
        }
        // Dropping a pack or a folder of recordings adds it, like the button.
        .dropDestination(for: URL.self) { urls, _ in
            importSwitchSet(from: urls)
            return true
        }
    }

    private func addSwitchSet() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.audio, .folder]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose a Mechvibes sound pack folder, a folder of key recordings, or the recordings themselves."
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

    private func remove(_ pack: SoundPack) {
        let alert = NSAlert()
        alert.messageText = "Remove \(pack.name)?"
        alert.informativeText = "Its sounds are moved to the Trash."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try state.removeSwitchSet(pack)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

// MARK: - Keys

private struct KeysPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
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
                Text("Also Play Sounds For")
            } footer: {
                footer("Letters, numbers, Space, Return and the other typing keys always play.")
            }

            Section {
                Toggle("Typewriter ding on Return", isOn: $state.returnDing)
                Toggle("Trackpad tap with each key", isOn: $state.hapticFeedback)
            } header: {
                Text("Extras")
            } footer: {
                footer("The trackpad tap needs a Force Touch trackpad.")
            }
        }
    }
}

// MARK: - Muting

private struct MutingPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                if MicrophoneMonitor.isSupported {
                    Toggle("During calls and recordings", isOn: $state.muteDuringCalls)
                }
                Toggle("While the screen is locked", isOn: $state.muteWhenLocked)
                Toggle("On speakers (headphones only)", isOn: $state.headphonesOnly)
                Picker("After no typing for", selection: $state.idleTimeoutMinutes) {
                    Text("Never").tag(0)
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                }
            } header: {
                Text("Mute Automatically")
            } footer: {
                footer((MicrophoneMonitor.isSupported
                      ? "Calls and recordings means any app using the microphone. \"Hey Siri\" doesn't count. "
                      : "")
                     + "Speakers means the Mac's own speakers, a display or AirPlay. Bluetooth, USB and wired headphones play.")
            }

            Section {
                MutedAppsList(state: state)
            } header: {
                Text("Mute in These Apps")
            } footer: {
                footer("ThockBox stays quiet while one of these apps is in front. The menu bar menu can also mute the app you're in.")
            }
        }
    }
}

// MARK: - Activity

private struct ActivityPage: View {
    @ObservedObject var store: StatsStore

    var body: some View {
        Form {
            Section("Keystrokes") {
                LabeledContent("Today", value: store.shown.today.formatted())
                LabeledContent("All time", value: store.shown.total.formatted())
            }

            Section("Last 7 Days") {
                if store.shown.lastWeek().allSatisfy({ $0.count == 0 }) {
                    Text("Nothing yet. Start typing and this fills in day by day.")
                        .foregroundStyle(.secondary)
                } else {
                    KeystrokeChart(store: store)
                }
            }
        }
    }
}

// MARK: - General

private struct GeneralPage: View {
    @ObservedObject var state: AppState
    @ObservedObject var updater = Updater.shared

    var body: some View {
        Form {
            AttentionSection(state: state)

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
                }
            } header: {
                Text("Updates")
            } footer: {
                if updater.availableRelease != nil && Updater.isAdHocSigned {
                    footer("After updating, macOS may ask you to allow Accessibility access again.")
                }
            }

            Section("Help") {
                LabeledContent("Accessibility access") {
                    if state.accessibilityTrusted {
                        Text("Allowed")
                    } else {
                        Button("Open System Settings") { Permissions.openSystemSettings() }
                    }
                }
                Link("Troubleshooting", destination: URL(string: "https://github.com/Bruno-Alumn/ThockBox#troubleshooting")!)
            }
        }
    }
}

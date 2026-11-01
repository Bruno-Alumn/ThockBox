import SwiftUI

/// The desktop window: every setting, with room to breathe. The menu bar
/// panel (MenuView) keeps only the quick ones.
struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var updater = Updater.shared

    var body: some View {
        Form {
            Section {
                header
                if !state.accessibilityTrusted {
                    PermissionBanner()
                }
                if let app = state.secureInputApp {
                    SecureInputBanner(app: app)
                }
            }

            Section {
                SwitchList(state: state)
            } header: {
                HStack {
                    Text("Switches")
                    Spacer()
                    PreviewButton(state: state)
                        .controlSize(.small)
                }
            }

            Section("Volume") {
                // labelsHidden: in a grouped Form an unlabeled slider would
                // otherwise sit in the value column, at half width.
                VolumeControl(state: state)
                    .labelsHidden()
            }

            Section {
                HStack(alignment: .top, spacing: 16) {
                    TonePadView(x: $state.toneX, y: $state.toneY)
                        .frame(width: 150, height: 150)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Drag left for a darker, deeper sound and right for a brighter, crisper one. Drag up or down to raise or lower the pitch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Randomize pitch")
                            .font(.caption)
                            .padding(.top, 4)
                        Slider(value: $state.pitchVariation, in: 0...150)
                            .labelsHidden()
                        Text("Small random pitch changes so repeated keys don't sound identical.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                HStack {
                    Text("Tone")
                    Spacer()
                    Button("Reset") {
                        state.toneX = 0
                        state.toneY = 0
                    }
                    .controlSize(.small)
                    .disabled(state.toneX == 0 && state.toneY == 0)
                }
            }

            Section("Keys") {
                LabeledContent("Toggle sounds") {
                    ShortcutRecorder(state: state)
                }
                Toggle("Mute modifier keys (⌘ ⌥ ⌃ ⇧)", isOn: $state.muteModifiers)
                Toggle("Play sounds for function keys", isOn: $state.functionKeysAudible)
                Toggle("Ding on Return", isOn: $state.returnDing)
                Toggle("Mouse click sounds", isOn: $state.mouseClicks)
                Toggle("Haptic feedback on the trackpad", isOn: $state.hapticFeedback)
            }

            Section {
                Toggle("Mute when the screen is locked", isOn: $state.muteWhenLocked)
                if MicrophoneMonitor.isSupported {
                    Toggle("Mute while another app uses the microphone", isOn: $state.muteDuringCalls)
                        .help("Keeps key sounds out of calls and recordings")
                }
                Picker("Mute after inactivity", selection: $state.idleTimeoutMinutes) {
                    Text("Off").tag(0)
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("60 minutes").tag(60)
                }
            } header: {
                Text("Automatic mute")
            } footer: {
                if let mute = state.automaticMute {
                    Text(mute.message)
                }
            }

            Section {
                MutedAppsList(state: state)
            } header: {
                Text("Muted apps")
            } footer: {
                Text("ThockBox stays quiet while one of these apps is in front.")
            }

            Section("Output") {
                OutputDevicePicker(state: state)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $state.launchAtLogin)
                Toggle("Notify when the switch changes", isOn: $state.notifyOnSwitchChange)
                LabeledContent("Keystrokes") {
                    StatsLine(store: state.stats)
                        .foregroundStyle(.secondary)
                }
                KeystrokeChart(store: state.stats)
            }

            Section {
                Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
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
        }
        .formStyle(.grouped)
        .tint(.thockCoral)
        .frame(minWidth: 460, idealWidth: 480, minHeight: 520, idealHeight: 720)
        .onAppear { state.refreshAccessibilityStatus() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("ThockBox")
                    .font(.title2.bold())
                Text("Sounds are \(state.enabled ? "on" : "off"). Toggle anytime with \(state.toggleShortcut.display).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Sounds", isOn: $state.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

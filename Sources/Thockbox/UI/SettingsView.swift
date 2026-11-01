import SwiftUI

/// The desktop window: every setting, with room to breathe. The menu bar
/// panel (MenuView) keeps only the quick ones.
struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                header
                if !state.accessibilityTrusted {
                    PermissionBanner()
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
                Toggle("Mute modifier keys (⌘ ⌥ ⌃ ⇧)", isOn: $state.muteModifiers)
                Toggle("Play sounds for function keys", isOn: $state.functionKeysAudible)
                Toggle("Ding on Return", isOn: $state.returnDing)
                Toggle("Mouse click sounds", isOn: $state.mouseClicks)
                Toggle("Haptic feedback on the trackpad", isOn: $state.hapticFeedback)
            }

            Section {
                Toggle("Mute when the screen is locked", isOn: $state.muteWhenLocked)
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
                if state.isAutomaticallyMuted {
                    Text("Automatic mute is on right now. Press any key to wake it.")
                }
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
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, idealWidth: 480, minHeight: 520, idealHeight: 720)
        .onAppear { state.refreshAccessibilityStatus() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Thockbox")
                    .font(.title2.bold())
                Text(state.enabled ? "Sounds are on. Toggle anytime with ⌘⌃K." : "Sounds are off. Toggle anytime with ⌘⌃K.")
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

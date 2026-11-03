import SwiftUI
import UniformTypeIdentifiers

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
        .onAppear { state.refreshOnOpen() }
    }
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
                if let until = state.offUntil {
                    formFooter("Off until \(until.formatted(date: .omitted, time: .shortened)), then back on by itself.")
                } else {
                    formFooter("Turn sounds on or off anytime with \(state.toggleShortcut.display).")
                }
            }

            Section {
                SwitchSetPicker(state: state)
                Toggle("A different set each day", isOn: $state.newSetEachDay)
                TryItField()
                HStack {
                    Button("Add Your Own…", action: addSwitchSet)
                    let added = state.packs.filter { UserPacks.isUserPack($0) }
                    if !added.isEmpty {
                        Menu("Your Sets") {
                            ForEach(added) { pack in
                                Menu(pack.name) {
                                    Button("Export…") { export(pack) }
                                    Button("Remove…") { remove(pack) }
                                }
                            }
                        }
                        .fixedSize()
                    }
                }
            } footer: {
                formFooter("Choosing a set plays a sample of it. Add a Mechvibes sound pack, a set exported from ThockBox, or a folder of your own recordings, or drop one on this window.")
            }

            Section {
                AppPacksList(state: state)
            } header: {
                Text("Sets for Specific Apps")
            } footer: {
                formFooter("These apps play their own set while they're in front, say a quieter one in Terminal. Every other app plays the set above.")
            }

            Section {
                Slider(value: $state.volume, in: 0...1) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill")
                }
                .accessibilityValue(SpokenValue.percent(state.volume))
                .sliderHaptics(state.volume, in: 0...1, step: 0.1)
                OutputDevicePicker(state: state)
                Toggle("Spatial audio on headphones", isOn: $state.spatialAudio)
                if #available(macOS 14, *), state.spatialAudio {
                    Toggle("Follow head movement (AirPods)", isOn: $state.followHeadMovement)
                }
            } footer: {
                formFooter("Each output device keeps its own volume. Spatial audio places each key around you in 3D; it works through headphones only. Following head movement keeps the keys in place as you turn your head.")
            }

            Section {
                Slider(value: $state.toneX, in: -1...1) {
                    Text("Brightness")
                } minimumValueLabel: {
                    Text("Darker")
                } maximumValueLabel: {
                    Text("Brighter")
                }
                .accessibilityValue(SpokenValue.direction(state.toneX, up: "brighter", down: "darker"))
                .sliderHaptics(state.toneX, in: -1...1, step: 1)
                Slider(value: $state.toneY, in: -1...1) {
                    Text("Pitch")
                } minimumValueLabel: {
                    Text("Lower")
                } maximumValueLabel: {
                    Text("Higher")
                }
                .accessibilityValue(SpokenValue.direction(state.toneY, up: "higher", down: "lower"))
                .sliderHaptics(state.toneY, in: -1...1, step: 1)
                Slider(value: $state.pitchVariation, in: 0...150) {
                    Text("Variation")
                } minimumValueLabel: {
                    Text("None")
                } maximumValueLabel: {
                    Text("More")
                }
                .accessibilityValue(SpokenValue.percent(state.pitchVariation, of: 150))
                Button("Reset Tone") {
                    state.toneX = 0
                    state.toneY = 0
                    state.pitchVariation = 60
                }
                .disabled(state.toneX == 0 && state.toneY == 0 && state.pitchVariation == 60)
            } header: {
                Text("Tone")
            } footer: {
                formFooter("Variation changes the pitch of each key a little, like a real keyboard.")
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
            showError("Couldn't Add the Switch Set", error)
        }
    }

    private func export(_ pack: SoundPack) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = pack.name
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "\(pack.name) is saved as a folder. Anyone can add it with Add Your Own."
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            try UserPacks.export(pack, as: target)
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } catch {
            showError("Couldn't Export \(pack.name)", error)
        }
    }

    /// A short title saying what failed, with the reason under it.
    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
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
            showError("Couldn't Remove \(pack.name)", error)
        }
    }
}

// MARK: - Keys

private struct KeysPage: View {
    @ObservedObject var state: AppState
    @State private var shortcutRejected = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Turn sounds on or off") {
                    ShortcutRecorder(state: state, rejected: $shortcutRejected)
                }
                LabeledContent("Next switch set") {
                    ShortcutRecorder(state: state, rejected: $shortcutRejected,
                                     shortcut: $state.nextSetShortcut, standard: nil)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                if shortcutRejected {
                    formFooter(Shortcut.requirement)
                } else if !Shortcut.isAllowed(state.toggleShortcut.flags) {
                    // Saved before the current rule: it still works, but the
                    // app in front gets the key too.
                    formFooter("The app in front also gets \(state.toggleShortcut.display). Record one with ⌃, or ⌘ with ⌥, to keep it to ThockBox.")
                }
            }

            Section {
                Toggle("Modifier keys (⌘ ⌥ ⌃ ⇧)", isOn: Binding(
                    get: { !state.muteModifiers },
                    set: { state.muteModifiers = !$0 }))
                Toggle("Function keys", isOn: $state.functionKeysAudible)
                Toggle("Mouse clicks", isOn: $state.mouseClicks)
                Toggle("Scrolling", isOn: $state.scrollSounds)
            } header: {
                Text("Also Play Sounds For")
            } footer: {
                formFooter("Letters, numbers, Space, Return and the other typing keys always play. Scrolling ticks softly, like a mouse wheel.")
            }

            Section {
                Toggle("Typewriter ding on Return", isOn: $state.returnDing)
                Toggle("Trackpad tap with each key", isOn: $state.hapticFeedback)
            } header: {
                Text("Extras")
            } footer: {
                formFooter("The trackpad tap needs a Force Touch trackpad. With scrolling sounds on, each scroll tick taps too.")
            }
        }
    }
}

// MARK: - Muting

/// Which calendars' events mute: all by default.
private struct CalendarChoice: View {
    @ObservedObject var state: AppState

    var body: some View {
        LabeledContent("Calendars") {
            Menu(CalendarMonitor.summary(state.calendars, ignoring: state.ignoredCalendarIDs)) {
                ForEach(state.calendars) { calendar in
                    Toggle(calendar.account.isEmpty ? calendar.title : "\(calendar.title) (\(calendar.account))",
                           isOn: Binding(
                            get: { !state.ignoredCalendarIDs.contains(calendar.id) },
                            set: { counts in
                                if counts { state.ignoredCalendarIDs.remove(calendar.id) }
                                else { state.ignoredCalendarIDs.insert(calendar.id) }
                            }))
                }
            }
            .fixedSize()
        }
    }
}

private struct MutingPage: View {
    @ObservedObject var state: AppState

    /// Minutes after midnight as a time of day for a DatePicker.
    static func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(minutes.wrappedValue) * 60) },
            set: { minutes.wrappedValue = AppState.minuteOfDay($0) })
    }

    var body: some View {
        Form {
            Section {
                if AudioActivityMonitor.isSupported {
                    Toggle("Calls and recordings", isOn: $state.muteDuringCalls)
                }
                Toggle("Calendar events", isOn: $state.muteDuringMeetings)
                if state.muteDuringMeetings && !state.calendars.isEmpty {
                    CalendarChoice(state: state)
                }
                if state.muteDuringMeetings && state.calendarAccess == .denied {
                    Text("ThockBox can't see your calendars. Allow it in System Settings › Privacy & Security › Calendars.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if ScreenCapture.isAvailable {
                    Toggle("Screen sharing and recording", isOn: $state.muteWhileSharing)
                }
                if AudioActivityMonitor.isSupported {
                    Toggle("Other apps playing sound", isOn: $state.muteWhileMedia)
                    if state.muteWhileMedia {
                        MediaAppsChoice(state: state)
                    }
                }
                Toggle("Games", isOn: $state.muteWhileGaming)
            } header: {
                Text("Mute During")
            } footer: {
                formFooter((AudioActivityMonitor.isSupported
                      ? "Calls and recordings means any app using the microphone; \"Hey Siri\" doesn't count. Other apps playing sound includes music and videos, but not alerts; some apps (call apps, a browser just after a video) keep their sound open while silent; uncheck them under Playing now. "
                      : "")
                     + "Calendar events don't count when they last all day, are marked free, or you declined them. A game is an app filed under Games, or one installed by Steam. Screen sharing also counts screen mirroring and apps that watch the screen in the background.")
            }

            Section {
                Toggle("The screen is locked", isOn: $state.muteWhenLocked)
                Toggle("Quiet hours", isOn: $state.quietHours)
                if state.quietHours {
                    LabeledContent("From") {
                        HStack {
                            DatePicker("From", selection: Self.time($state.quietStart), displayedComponents: .hourAndMinute)
                            Text("to")
                            DatePicker("To", selection: Self.time($state.quietEnd), displayedComponents: .hourAndMinute)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                Toggle("Playing on speakers (headphones only)", isOn: $state.headphonesOnly)
                Picker("No typing for", selection: $state.idleTimeoutMinutes) {
                    Text("Never").tag(0)
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                }
            } header: {
                Text("Mute When")
            } footer: {
                formFooter("Speakers means the Mac's own speakers, a display or AirPlay. Bluetooth, USB and wired headphones play.")
            }

            Section {
                MutedAppsList(state: state)
            } header: {
                Text("Mute in These Apps")
            } footer: {
                formFooter("ThockBox stays quiet while one of these apps is in front. The menu bar menu can also mute the app you're in.")
            }
        }
    }
}

// MARK: - Activity

private struct ActivityPage: View {
    @ObservedObject var store: StatsStore

    /// "Monday, Nov 2" for a "2026-11-02" stamp, or the stamp if it won't parse.
    static func dayName(_ stamp: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: stamp) else { return stamp }
        if Calendar.current.isDateInToday(date) { return "today" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Today", value: store.shown.today.formatted())
                LabeledContent("All time", value: store.shown.total.formatted())
                LabeledContent("Typing speed today") {
                    if let wpm = store.shown.wordsPerMinute {
                        Text("\(wpm) words per minute")
                    } else {
                        Text("Keep typing").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Keystrokes")
            } footer: {
                formFooter("Typing speed counts five keystrokes as a word and leaves out pauses longer than two seconds.")
            }

            if let best = store.shown.bestDay {
                Section("Last 30 Days") {
                    LabeledContent("Best day") {
                        Text("\(best.count.formatted()) on \(Self.dayName(best.date))")
                    }
                    if let average = store.shown.dailyAverage {
                        LabeledContent("Daily average", value: average.formatted())
                    }
                }
            }

            Section("Last 7 Days") {
                if store.shown.lastWeek().allSatisfy({ $0.count == 0 }) {
                    Text("Nothing yet. Start typing and this fills in day by day.")
                        .foregroundStyle(.secondary)
                } else {
                    KeystrokeChart(store: store)
                }
            }

            Section {
                LabeledContent("Daily counts") {
                    Button("Export…") { exportCSV() }
                }
            } footer: {
                formFooter("A CSV of the last 30 days, for a spreadsheet. Only counts are kept, never what you typed.")
            }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ThockBox Keystrokes.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.shown.csv().write(to: url, atomically: true, encoding: .utf8)
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
                if state.showMenuBarIcon {
                    Picker(selection: $state.iconClickAction) {
                        ForEach(IconClickAction.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Text("Clicking the icon")
                        if state.iconClickAction == .toggleSounds {
                            Text("Control-click opens the menu.")
                        }
                    }
                }
                Picker(selection: $state.dockIconStyle) {
                    ForEach(DockIconStyle.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("App icon")
                    Text("Shown in the Dock and ThockBox's windows.")
                }
                Toggle("Show today's keystrokes in the menu bar", isOn: $state.showKeystrokesInMenuBar)
                Toggle("Show today's typing speed in the menu bar", isOn: $state.showSpeedInMenuBar)
                Toggle("Dim the icon while sounds are off", isOn: $state.dimIconWhenOff)
                    .disabled(!state.showMenuBarIcon)
                Toggle(isOn: $state.notifySetChanges) {
                    Text("Notify when the switch set changes")
                    Text("When a Focus, Shortcuts or AppleScript picks a different set.")
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
                    formFooter("After updating, macOS may ask you to allow Accessibility access again.")
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
                LabeledContent("Getting started") {
                    HStack {
                        Button("Welcome…") { WelcomeWindow.shared.show() }
                        Button("What's New…") { WhatsNewWindow.shared.show() }
                    }
                }
                Link("Troubleshooting", destination: URL(string: "https://github.com/Bruno-Alumn/ThockBox#troubleshooting")!)
                Link("Report a Problem…", destination: ProblemReport.url())
            }
        }
    }
}

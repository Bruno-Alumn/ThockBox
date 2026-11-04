import SwiftUI
import UniformTypeIdentifiers

/// The settings window's pages, one per sidebar row (see MainWindow). Each is
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

    var sidebarSymbol: String {
        switch self {
        case .sound: "speaker.wave.2.fill"
        case .keys: "keyboard.fill"
        case .muting: "speaker.slash.fill"
        case .activity: "chart.bar.fill"
        case .general: "gearshape.fill"
        }
    }

    /// The same families System Settings uses: red for sound, purple for
    /// Focus-like quiet, blue for Screen Time-like stats, gray for the rest.
    var color: Color {
        switch self {
        case .sound: .red
        case .keys: .gray
        case .muting: .indigo
        case .activity: .blue
        case .general: .gray
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
        .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
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
                    HStack {
                        Button("Reset…", action: confirmAccessibilityReset)
                        Button("Open System Settings") { Permissions.openSystemSettings() }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    /// Already switched on in System Settings but still not allowed: a stale
    /// entry macOS won't match to this build. Clearing it brings the prompt
    /// back.
    private func confirmAccessibilityReset() {
        let alert = NSAlert()
        alert.messageText = "Reset Accessibility Access?"
        alert.informativeText = "Use this when ThockBox is switched on in System Settings › Privacy & Security › Accessibility but still can't hear keys. ThockBox is removed from that list, then asks to be allowed again."
        alert.addButton(withTitle: "Reset").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Permissions.reset()
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
                    formFooter("Back on at \(until.formatted(date: .omitted, time: .shortened)).")
                } else {
                    formFooter("Shortcut: \(state.toggleShortcut.display)")
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
                .frame(maxWidth: .infinity, alignment: .trailing)
            } footer: {
                formFooter("Add a Mechvibes pack or a folder of recordings, or drop one on this window.")
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
                formFooter("Each output device keeps its own volume.")
            }

            Section {
                Slider(value: $state.toneX, in: -1...1) {
                    Text("Brightness")
                } minimumValueLabel: {
                    Text("Darker").toneEnd(.trailing)
                } maximumValueLabel: {
                    Text("Brighter").toneEnd(.leading)
                }
                .accessibilityValue(SpokenValue.direction(state.toneX, up: "brighter", down: "darker"))
                .sliderHaptics(state.toneX, in: -1...1, step: 1)
                Slider(value: $state.toneY, in: -1...1) {
                    Text("Pitch")
                } minimumValueLabel: {
                    Text("Lower").toneEnd(.trailing)
                } maximumValueLabel: {
                    Text("Higher").toneEnd(.leading)
                }
                .accessibilityValue(SpokenValue.direction(state.toneY, up: "higher", down: "lower"))
                .sliderHaptics(state.toneY, in: -1...1, step: 1)
                Slider(value: $state.pitchVariation, in: 0...150) {
                    Text("Variation")
                } minimumValueLabel: {
                    Text("None").toneEnd(.trailing)
                } maximumValueLabel: {
                    Text("More").toneEnd(.leading)
                }
                .accessibilityValue(SpokenValue.percent(state.pitchVariation, of: 150))
                Button("Reset Tone") {
                    state.toneX = 0
                    state.toneY = 0
                    state.pitchVariation = 60
                }
                .disabled(state.toneX == 0 && state.toneY == 0 && state.pitchVariation == 60)
                .frame(maxWidth: .infinity, alignment: .trailing)
            } header: {
                Text("Tone")
            } footer: {
                formFooter("Variation gives each key a slightly different pitch.")
            }

            Section {
                AppPacksList(state: state)
            } header: {
                Text("Sets for Specific Apps")
            } footer: {
                formFooter("These apps play their own set while they're in front.")
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
        alert.addButton(withTitle: "Remove").hasDestructiveAction = true
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
                                     shortcut: $state.nextSetShortcut, standard: nil, title: "Next switch set")
                }
                LabeledContent("Volume up") {
                    ShortcutRecorder(state: state, rejected: $shortcutRejected,
                                     shortcut: $state.volumeUpShortcut, standard: nil, title: "Volume up")
                }
                LabeledContent("Volume down") {
                    ShortcutRecorder(state: state, rejected: $shortcutRejected,
                                     shortcut: $state.volumeDownShortcut, standard: nil, title: "Volume down")
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
                Toggle("Modifier keys (⌃ ⌥ ⇧ ⌘)", isOn: Binding(
                    get: { !state.muteModifiers },
                    set: { state.muteModifiers = !$0 }))
                Toggle("Function keys", isOn: $state.functionKeysAudible)
                Toggle("Key releases", isOn: $state.keyReleaseSounds)
                Toggle(isOn: $state.generatedKeySounds) {
                    Text("Keys typed by other apps")
                    Text("From text expanders, password managers and remote control.")
                }
                Toggle("Mouse clicks", isOn: $state.mouseClicks)
                Toggle("Scrolling", isOn: $state.scrollSounds)
            } header: {
                Text("Also Play Sounds For")
            } footer: {
                formFooter("Letters, numbers and other typing keys always play.")
            }

            Section {
                Toggle("Typewriter ding on Return", isOn: $state.returnDing)
                Toggle(isOn: $state.hapticFeedback) {
                    Text("Trackpad tap with each key")
                    if state.hapticFeedback {
                        Text("Needs a Force Touch trackpad.")
                    }
                }
            } header: {
                Text("Extras")
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

    /// One line for each Mute During option that's on, where it isn't obvious.
    private var muteDuringNote: String? {
        let notes = [
            state.muteDuringMeetings ? "All-day, free and declined events don't count." : nil,
            ScreenCapture.isAvailable && state.muteWhileSharing ? "Screen sharing includes mirroring and apps that watch the screen." : nil,
            AudioActivityMonitor.isSupported && state.muteWhileMedia ? "If an app keeps its sound open while silent, uncheck it under Playing now." : nil,
            state.muteWhileGaming ? "Games are apps filed under Games or installed by Steam." : nil,
        ].compactMap { $0 }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    var body: some View {
        Form {
            Section {
                if AudioActivityMonitor.isSupported {
                    Toggle("Calls and recordings", isOn: $state.muteDuringCalls)
                }
                Toggle(isOn: $state.muteDuringMeetings) {
                    Text("Calendar events")
                    if state.muteDuringMeetings && state.calendarAccess == .denied {
                        Text("ThockBox can't see your calendars. Allow it in System Settings › Privacy & Security › Calendars.")
                    }
                }
                if state.muteDuringMeetings && !state.calendars.isEmpty {
                    CalendarChoice(state: state)
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
                if let note = muteDuringNote {
                    formFooter(note)
                }
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
                Toggle("Playing on speakers", isOn: $state.headphonesOnly)
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
                if state.headphonesOnly {
                    formFooter("Speakers include displays and AirPlay. Bluetooth, USB and wired audio still play.")
                }
            }

            if PlaceMonitor.isAvailable {
                Section {
                    Toggle(isOn: $state.muteByPlace) {
                        Text("Use your location")
                        if state.muteByPlace && state.locationAccess == .denied {
                            Text("ThockBox can't use your location. Allow it in System Settings › Privacy & Security › Location Services.")
                        }
                    }
                    if state.muteByPlace {
                        Picker("These places", selection: $state.playOnlyAtPlaces) {
                            Text("Stay quiet at them").tag(false)
                            Text("Are the only ones that play").tag(true)
                        }
                        PlacesList(state: state)
                    }
                } header: {
                    Text(state.muteByPlace && state.playOnlyAtPlaces ? "Play Only at These Places" : "Mute at These Places")
                } footer: {
                    if state.muteByPlace {
                        formFooter("Add a place while you're there. Your location stays on this Mac, except that adding a place asks Apple for its address to name it.")
                    }
                }
            }

            Section {
                Picker("These apps", selection: $state.playOnlyInListedApps) {
                    Text("Stay quiet in them").tag(false)
                    Text("Are the only ones that play").tag(true)
                }
                MutedAppsList(state: state)
            } header: {
                Text(state.playOnlyInListedApps ? "Play Only in These Apps" : "Mute in These Apps")
            } footer: {
                if state.playOnlyInListedApps {
                    formFooter("Every other app stays quiet.")
                }
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
                LabeledContent("Today") { Text(store.shown.today.formatted()).monospacedDigit() }
                LabeledContent("All time") { Text(store.shown.total.formatted()).monospacedDigit() }
                LabeledContent("Typing speed today") {
                    if let wpm = store.shown.wordsPerMinute {
                        Text("\(wpm) words per minute").monospacedDigit()
                    } else {
                        Text("Not enough typing yet").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Keystrokes")
            } footer: {
                formFooter("Typing speed counts five keystrokes as a word and leaves out pauses over two seconds. Only counts are kept, never what you type.")
            }

            if store.shown.today > 0 {
                Section("Today by Hour") {
                    HourlyChart(store: store)
                }
            }

            Section("Last 7 Days") {
                if store.shown.lastWeek().allSatisfy({ $0.count == 0 }) {
                    Text("Nothing yet.")
                        .foregroundStyle(.secondary)
                } else {
                    KeystrokeChart(store: store)
                }
            }

            if let best = store.shown.bestDay {
                Section("Last 30 Days") {
                    LabeledContent("Best day") {
                        let day = Self.dayName(best.date)
                        if day == "today" {
                            Text("\(best.count.formatted()) today").monospacedDigit()
                        } else {
                            Text("\(best.count.formatted()) on \(day)").monospacedDigit()
                        }
                    }
                    if let average = store.shown.dailyAverage {
                        LabeledContent("Daily average", value: average.formatted())
                    }
                    let streak = store.shown.streak()
                    if streak >= 2 {
                        LabeledContent("Streak", value: "\(streak) days in a row")
                    }
                }
            }

            Section {
                LabeledContent("Last 30 days") {
                    Button("Export as CSV…") { exportCSV() }
                }
            }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ThockBox Keystrokes.csv"
        panel.prompt = "Export"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.shown.csv().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't Export Daily Counts"
            alert.informativeText = error.localizedDescription
            alert.runModal()
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
                Picker(selection: $state.dockIconStyle) {
                    ForEach(DockIconStyle.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("App icon")
                }
                Toggle(isOn: $state.notifySetChanges) {
                    Text("Notify when the switch set changes")
                    Text("When a Focus, Shortcuts or AppleScript picks a different set.")
                }
            }

            Section("Menu Bar") {
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
                    Toggle("Show today's keystrokes", isOn: $state.showKeystrokesInMenuBar)
                    Toggle("Show today's typing speed", isOn: $state.showSpeedInMenuBar)
                    Toggle("Dim the icon while sounds are off", isOn: $state.dimIconWhenOff)
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
                LabeledContent("Getting started") {
                    HStack {
                        Button("Welcome") { WelcomeWindow.shared.show() }
                        Button("What's New") { WhatsNewWindow.shared.show() }
                    }
                }
                LabeledContent("Settings") {
                    HStack {
                        Button("Export…", action: exportSettings)
                        Button("Import…", action: importSettings)
                    }
                }
                Link("Troubleshooting", destination: URL(string: "https://github.com/Bruno-Alumn/ThockBox#troubleshooting")!)
                Link("Report a Problem…", destination: ProblemReport.url())
            }
        }
    }

    /// Saves this Mac's settings to bring to another one.
    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ThockBox Settings.plist"
        panel.prompt = "Export"
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsTransfer.export(from: .standard).write(to: url)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't Export Settings"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// Applies an exported file and restarts ThockBox to pick it all up.
    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsTransfer.importSettings(Data(contentsOf: url), into: .standard)
            SettingsTransfer.relaunch()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't Import Settings"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

private extension View {
    /// The words at each end of a Tone slider, in a fixed width so the three
    /// sliders line up.
    func toneEnd(_ alignment: Alignment) -> some View {
        frame(width: 52, alignment: alignment)
    }
}

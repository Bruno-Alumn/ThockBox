import AppKit
import Combine
import CoreAudio
import ServiceManagement

/// Central app state: user settings (persisted to UserDefaults), the audio
/// engine, the key listener, and keystroke stats.
final class AppState: ObservableObject {
    static let shared = AppState()

    let engine = SoundEngine()
    let listener = KeyListener()
    /// Bundled switch sets plus any the user added (see UserPacks).
    @Published private(set) var packs: [SoundPack] = []

    // MARK: - Persisted settings

    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "enabled")
            // Turning sounds on by hand ends a timed off.
            if enabled { setOffUntil(nil) }
            syncEngineState()
        }
    }
    /// When sounds come back after Turn Off for an Hour; nil otherwise.
    @Published private(set) var offUntil: Date?
    private var resumeTimer: Timer?

    /// What the Focus filter changed from, to put back when the Focus ends.
    /// Saved, so a relaunch during a Focus still restores it afterwards.
    struct FocusBefore: Codable, Equatable {
        var enabled: Bool
        var packID: String
        /// Whether a Focus turned sounds off; only then are they turned back.
        var turnedOff = false
    }

    private var beforeFocus: FocusBefore? {
        get {
            defaults.data(forKey: "focusBefore").flatMap { try? JSONDecoder().decode(FocusBefore.self, from: $0) }
        }
        set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "focusBefore")
        }
    }

    /// Applies a Focus filter. Default values (sounds on, no set) mean the
    /// Focus ended: put back what was there before it started. A Focus that
    /// only picks a set leaves on/off alone, so it doesn't cancel a timed
    /// off or undo turning sounds off by hand.
    func applyFocusFilter(soundsOn: Bool, packID: String?) {
        guard !soundsOn || packID != nil else {
            if let before = beforeFocus {
                beforeFocus = nil
                selectPackFromElsewhere(before.packID)
                if before.turnedOff { enabled = before.enabled }
            }
            return
        }
        var before = beforeFocus ?? FocusBefore(enabled: enabled, packID: selectedPackID)
        if let packID { selectPackFromElsewhere(packID) }
        if !soundsOn {
            before.turnedOff = true
            enabled = false
        } else if before.turnedOff {
            // Switched from a Focus that turned sounds off to one that doesn't.
            before.turnedOff = false
            enabled = before.enabled
        }
        beforeFocus = before
    }

    /// Turns sounds off and back on by themselves after `duration`, even
    /// across a relaunch. Turning them on sooner cancels it.
    func turnOff(for duration: TimeInterval, now: Date = Date()) {
        enabled = false
        setOffUntil(now.addingTimeInterval(duration))
    }

    private func setOffUntil(_ date: Date?) {
        resumeTimer?.invalidate()
        resumeTimer = nil
        if offUntil != date { offUntil = date }
        defaults.set(date, forKey: "offUntil")
        guard let date else { return }
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            self?.resumeIfDue()
        }
        RunLoop.main.add(timer, forMode: .common)
        resumeTimer = timer
    }

    /// Internal so tests can pass a time. Also run on wake and whenever the
    /// menu or Settings opens: the timer runs on elapsed time, so after the
    /// clock is set back or a sleep it can fire early or be missed.
    func resumeIfDue(now: Date = Date()) {
        guard let offUntil else { return }
        if now >= offUntil {
            enabled = true
        } else if resumeTimer?.isValid != true {
            setOffUntil(offUntil) // fired early: wait again
        }
    }
    @Published var volume: Float {
        didSet {
            defaults.set(volume, forKey: "volume")
            engine.volume = volume
            if let device = activeOutputUID {
                volumeByDevice[device] = volume
                defaults.set(volumeByDevice, forKey: "volumeByDevice")
            }
            if !restoringVolume { scheduleVolumePreview() }
        }
    }
    @Published var selectedPackID: String {
        didSet {
            defaults.set(selectedPackID, forKey: "pack")
            applyPack(notify: oldValue != selectedPackID)
        }
    }
    /// Notify when Shortcuts or AppleScript changes the switch set.
    @Published var notifySetChanges: Bool {
        didSet {
            defaults.set(notifySetChanges, forKey: "notifySetChanges")
            if notifySetChanges && postsNotifications { SetChangeNotifier.requestPermission() }
        }
    }
    /// Tests turn this off: notifications need a signed app bundle.
    var postsNotifications = true
    @Published var toneX: Float {
        didSet {
            defaults.set(toneX, forKey: "toneX")
            engine.setTone(x: toneX, y: toneY)
        }
    }
    @Published var toneY: Float {
        didSet {
            defaults.set(toneY, forKey: "toneY")
            engine.setTone(x: toneX, y: toneY)
        }
    }
    @Published var pitchVariation: Float {
        didSet {
            defaults.set(pitchVariation, forKey: "pitchVariation")
            engine.pitchVariationCents = pitchVariation
        }
    }
    @Published var muteModifiers: Bool {
        didSet { defaults.set(muteModifiers, forKey: "muteModifiers") }
    }
    @Published var functionKeysAudible: Bool {
        didSet { defaults.set(functionKeysAudible, forKey: "functionKeysAudible") }
    }
    @Published var returnDing: Bool {
        didSet {
            defaults.set(returnDing, forKey: "returnDing")
            if returnDing && oldValue != returnDing { engine.playExtra(named: "ding") }
        }
    }
    @Published var mouseClicks: Bool {
        didSet {
            defaults.set(mouseClicks, forKey: "mouseClicks")
            listener.listensToMouse = mouseClicks
            if mouseClicks && oldValue != mouseClicks {
                engine.playExtra(named: "click_down", gain: 0.9)
            }
        }
    }
    /// A soft tick per notch of scrolling, plus a trackpad tap when
    /// hapticFeedback is on.
    @Published var scrollSounds: Bool {
        didSet {
            defaults.set(scrollSounds, forKey: "scrollSounds")
            listener.listensToScroll = scrollSounds
        }
    }
    @Published var hapticFeedback: Bool {
        didSet { defaults.set(hapticFeedback, forKey: "hapticFeedback") }
    }
    /// Hidden, ThockBox keeps running; opening it again from Finder or
    /// Spotlight shows the settings window. macOS also turns this off when
    /// the icon is ⌘-dragged out of the menu bar.
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }
    /// The menu bar icon is drawn fainter while keys make no sound.
    @Published var dimIconWhenOff: Bool {
        didSet { defaults.set(dimIconWhenOff, forKey: "dimIconWhenOff") }
    }
    /// Today's keystrokes next to the menu bar icon.
    @Published var showKeystrokesInMenuBar: Bool {
        didSet { defaults.set(showKeystrokesInMenuBar, forKey: "showKeystrokesInMenuBar") }
    }
    @Published var dockIconStyle: DockIconStyle {
        didSet { defaults.set(dockIconStyle.rawValue, forKey: "dockIconStyle") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            guard !reconcilingLoginItem else { return }
            updateLoginItem()
        }
    }
    /// Quiet while another app plays sound: music, a video, a game.
    @Published var muteWhileMedia: Bool {
        didSet {
            defaults.set(muteWhileMedia, forKey: "muteWhileMedia")
            updateMediaMonitor()
        }
    }
    /// Quiet while the screen is shared or recorded (a call, QuickTime).
    @Published var muteWhileSharing: Bool {
        didSet {
            defaults.set(muteWhileSharing, forKey: "muteWhileSharing")
            updateScreenShareWatch()
        }
    }
    /// Quiet while a game is in front.
    @Published var muteWhileGaming: Bool {
        didSet {
            defaults.set(muteWhileGaming, forKey: "muteWhileGaming")
            updateAutomaticMute()
        }
    }
    /// Quiet during calendar events (meetings), once Calendars access is
    /// allowed.
    @Published var muteDuringMeetings: Bool {
        didSet {
            defaults.set(muteDuringMeetings, forKey: "muteDuringMeetings")
            updateCalendarMonitor()
        }
    }
    @Published var muteWhenLocked: Bool {
        didSet {
            defaults.set(muteWhenLocked, forKey: "muteWhenLocked")
            updateAutomaticMute()
        }
    }
    @Published var muteDuringCalls: Bool {
        didSet {
            defaults.set(muteDuringCalls, forKey: "muteDuringCalls")
            updateMicrophoneMonitor()
            updateAutomaticMute()
        }
    }
    /// Bundle IDs of apps that ThockBox stays quiet in while they're in front.
    @Published var mutedApps: [String] {
        didSet {
            defaults.set(mutedApps, forKey: "mutedApps")
            updateAutomaticMute()
        }
    }
    @Published var toggleShortcut: Shortcut {
        didSet {
            defaults.set(try? JSONEncoder().encode(toggleShortcut), forKey: "toggleShortcut")
            registerHotKey()
        }
    }
    /// Set while Settings records a new shortcut, so pressing the current
    /// one there doesn't also toggle sounds.
    var isRecordingShortcut = false {
        didSet { registerHotKey() }
    }
    /// The shortcut as a system hotkey. While it's nil (recording, or macOS
    /// refused the combination), the key monitor matches it instead.
    private var hotKey: GlobalHotKey?
    /// Set by startUp; tests that never start the app use the key monitor.
    private var registersHotKeys = false
    /// Whether the shortcut is a system hotkey right now (for tests).
    var usesSystemHotKey: Bool { hotKey != nil }

    /// Internal so tests can turn hotkeys on without starting the app.
    func startHotKeys() {
        registersHotKeys = true
        registerHotKey()
    }

    private func registerHotKey() {
        hotKey = nil
        guard registersHotKeys else { return }
        // The health-check copy (launch_check.sh) mustn't take the key from
        // the real app.
        guard !isRecordingShortcut, !CommandLine.arguments.contains("--health-check") else { return }
        // A shortcut saved before the stricter rule (⌥K, ⌘⇧S) stays with the
        // key monitor, which only listens: as a system hotkey it would stop
        // reaching every app.
        guard Shortcut.isAllowed(toggleShortcut.flags) else { return }
        hotKey = GlobalHotKey(toggleShortcut) { [weak self] in
            guard let self else { return }
            enabled.toggle()
            // The key-ups still reach the monitors; don't let them play.
            suppressReleasesAfterShortcut()
        }
        if hotKey == nil { klog.error("couldn't register \(self.toggleShortcut.display, privacy: .public) as a hotkey") }
    }
    /// Stay quiet unless the sound goes into headphones, for offices and
    /// shared rooms.
    @Published var headphonesOnly: Bool {
        didSet {
            defaults.set(headphonesOnly, forKey: "headphonesOnly")
            updateAutomaticMute()
        }
    }
    @Published var idleTimeoutMinutes: Int {
        didSet {
            defaults.set(idleTimeoutMinutes, forKey: "idleTimeoutMinutes")
            idleMode.recordActivity()
            updateIdleTimer()
            updateAutomaticMute()
        }
    }
    private var reconcilingLoginItem = false
    @Published var outputDeviceUID: String? {
        didSet {
            defaults.set(outputDeviceUID, forKey: "outputDeviceUID")
            // Kept so Settings can still name the device while it's unplugged.
            if let uid = outputDeviceUID,
               let device = AudioDevices.outputDevices().first(where: { $0.uid == uid }) {
                defaults.set(device.name, forKey: "outputDeviceName")
            }
            outputRouteChanged()
            applyOutputDevice()
        }
    }
    /// The picked device's name as last seen connected.
    var outputDeviceName: String? { defaults.string(forKey: "outputDeviceName") }
    /// A picker change made while sounds are off or automatically muted is
    /// applied on resume; otherwise System Default could keep the old device.
    private var outputChangedWhileDisabled = false

    // MARK: - Stats

    let stats: StatsStore

    @Published private(set) var accessibilityTrusted = Permissions.isTrusted
    /// Checked when the menu or settings window opens; see SecureInput.
    @Published private(set) var secureInputApp: String?
    /// Why sounds are automatically muted right now, if they are.
    @Published private(set) var automaticMute: AutomaticMute?
    var isAutomaticallyMuted: Bool { automaticMute != nil }
    /// Another app is recording (only tracked while muteDuringCalls is on).
    @Published private(set) var microphoneInUse = false
    /// Another app is playing sound (only tracked while muteWhileMedia is on).
    @Published private(set) var mediaPlaying = false
    /// A calendar event is on (only tracked while muteDuringMeetings is on).
    @Published private(set) var inCalendarEvent = false
    /// Whether ThockBox may read calendars, once it has asked.
    @Published private(set) var calendarAccess = CalendarMonitor.Access.unknown
    /// The Mac's calendars, once access is allowed, for choosing which count.
    @Published private(set) var calendars: [CalendarMonitor.CalendarInfo] = []
    /// Calendars whose events don't mute.
    @Published var ignoredCalendarIDs: Set<String> {
        didSet {
            defaults.set(Array(ignoredCalendarIDs), forKey: "ignoredCalendars")
            calendarMonitor?.ignoredCalendarIDs = ignoredCalendarIDs
        }
    }

    private let defaults: UserDefaults
    private var idleMode = IdleMode()
    private var dynamics = TypingDynamics()
    private var scrollTicker = ScrollTicker()
    private var screenLocked = false
    private var screenShared = false
    private var screenShareTimer: Timer?
    /// Whether something captures the screen right now; tests replace it.
    var isScreenCaptured: () -> Bool = { ScreenCapture.isActive }
    private var microphoneMonitor: AudioActivityMonitor?
    private var mediaMonitor: AudioActivityMonitor?
    private var calendarMonitor: CalendarMonitor?
    /// Tests turn this off: reading calendars asks the user for access.
    var readsCalendars = true
    /// Each output device keeps its own volume, as macOS does for system
    /// volume: headphones usually want less than speakers.
    private var volumeByDevice: [String: Float]
    private(set) var activeOutputUID: String?
    private var restoringVolume = false
    private var outputListeners: [SystemAudioListener] = []
    private var dataSourceListener: SystemAudioListener?
    /// The active output plays out loud (see AudioDevices.isSpeaker).
    private(set) var outputIsSpeaker = false
    /// The app in front, not counting ThockBox itself: opening the menu bar
    /// panel or settings window leaves it pointing at the app you came from.
    @Published private(set) var frontApp: FrontApp?

    /// The app uses `shared` (standard defaults); tests pass their own store.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "enabled": true, "volume": 0.55, "pack": "cream",
            "toneX": 0.0, "toneY": 0.0, "pitchVariation": 60.0,
            "muteModifiers": false, "functionKeysAudible": true,
            "returnDing": false, "mouseClicks": false,
            "hapticFeedback": false, "scrollSounds": false,
            "launchAtLogin": false, "showMenuBarIcon": true, "dimIconWhenOff": true, "muteWhenLocked": false, "muteWhileSharing": false, "headphonesOnly": false, "muteDuringCalls": false,
            "muteDuringMeetings": false,
            "muteWhileMedia": false,
            "muteWhileGaming": false,
            "idleTimeoutMinutes": 0, "notifySetChanges": false,
        ])
        enabled = defaults.bool(forKey: "enabled")
        volume = min(max(defaults.float(forKey: "volume"), 0), 1)
        selectedPackID = defaults.string(forKey: "pack") ?? "cream"
        notifySetChanges = defaults.bool(forKey: "notifySetChanges")
        toneX = min(max(defaults.float(forKey: "toneX"), -1), 1)
        toneY = min(max(defaults.float(forKey: "toneY"), -1), 1)
        pitchVariation = min(max(defaults.float(forKey: "pitchVariation"), 0), 150)
        muteModifiers = defaults.bool(forKey: "muteModifiers")
        functionKeysAudible = defaults.bool(forKey: "functionKeysAudible")
        returnDing = defaults.bool(forKey: "returnDing")
        mouseClicks = defaults.bool(forKey: "mouseClicks")
        hapticFeedback = defaults.bool(forKey: "hapticFeedback")
        scrollSounds = defaults.bool(forKey: "scrollSounds")
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        dockIconStyle = defaults.string(forKey: "dockIconStyle").flatMap(DockIconStyle.init) ?? .color
        dimIconWhenOff = defaults.bool(forKey: "dimIconWhenOff")
        showKeystrokesInMenuBar = defaults.bool(forKey: "showKeystrokesInMenuBar")
        muteWhenLocked = defaults.bool(forKey: "muteWhenLocked")
        muteWhileSharing = defaults.bool(forKey: "muteWhileSharing")
        muteDuringCalls = defaults.bool(forKey: "muteDuringCalls")
        muteWhileGaming = defaults.bool(forKey: "muteWhileGaming")
        muteWhileMedia = defaults.bool(forKey: "muteWhileMedia")
        muteDuringMeetings = defaults.bool(forKey: "muteDuringMeetings")
        ignoredCalendarIDs = Set(defaults.stringArray(forKey: "ignoredCalendars") ?? [])
        headphonesOnly = defaults.bool(forKey: "headphonesOnly")
        mutedApps = defaults.stringArray(forKey: "mutedApps") ?? []
        toggleShortcut = defaults.data(forKey: "toggleShortcut")
            .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .standard
        idleTimeoutMinutes = max(0, defaults.integer(forKey: "idleTimeoutMinutes"))
        outputDeviceUID = defaults.string(forKey: "outputDeviceUID")
        volumeByDevice = defaults.dictionary(forKey: "volumeByDevice") as? [String: Float] ?? [:]
        stats = StatsStore(defaults: defaults)
        // A timed off still running from before a relaunch: keep its timer,
        // or turn sounds back on if it ran out while ThockBox was closed.
        if !enabled, let until = defaults.object(forKey: "offUntil") as? Date {
            setOffUntil(until)
            resumeIfDue()
        }
    }

    // MARK: - Lifecycle

    func startUp() {
        reloadPacks()
        engine.volume = volume
        engine.pitchVariationCents = pitchVariation
        engine.setTone(x: toneX, y: toneY)
        applyPack(notify: false)
        engine.loadExtras(from: Self.soundsDirectory().appendingPathComponent("_extras"))
        startHotKeys()
        if let session = CGSessionCopyCurrentDictionary() as NSDictionary? {
            screenLocked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        }
        updateMicrophoneMonitor()
        updateMediaMonitor()
        updateCalendarMonitor()
        updateScreenShareWatch()
        outputRouteChanged()
        outputListeners = SystemAudioListener.outputRoute { [weak self] in self?.outputRouteChanged() }
        setFrontApp(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.setFrontApp(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        updateAutomaticMute()
        syncEngineState()

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.setScreenLocked(true)
        }
        distributed.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.setScreenLocked(false)
        }
        updateIdleTimer()

        // NSEvent monitor callbacks arrive on the main thread already; calling
        // straight through keeps keystroke→sound latency at one buffer.
        engine.onFallbackToDefault = { [weak self] in
            self?.appliedOutputDevice = AudioDevices.defaultOutputDevice()
        }
        listener.handler = { [weak self] event in
            self?.handle(event)
        }
        accessibilityTrusted = Permissions.requestIfNeeded()
        listener.listensToMouse = mouseClicks
        listener.listensToScroll = scrollSounds
        listener.start()
        reconcileLoginItem()
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.stats.rollOver()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.resumeIfDue()
        }
        klog.notice("startup: trusted=\(self.accessibilityTrusted, privacy: .public) packs=\(self.packs.count, privacy: .public) device=\(self.outputDeviceUID ?? "default", privacy: .public)")

        // Monitors registered without Accessibility access don't recover
        // in-process. Watch both directions so a revoked then restored grant
        // gets the same fresh process as a grant made on first launch.
        wasTrusted = accessibilityTrusted
        scheduleAccessibilityCheck()
        // A menu-style menu bar item has no onAppear; refresh the status
        // (Accessibility, secure input) whenever one of our menus opens.
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshOnOpen()
        }
        // Posted when any app's Accessibility access changes, so a revoke is
        // usually seen right away instead of at the next slow poll. The
        // trust state can lag the notification slightly, hence the delay.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.checkAccessibility() }
        }
    }

    private var wasTrusted = false
    private var accessibilityTimer: Timer?

    /// Every 2 s while waiting for a grant (the user is in System Settings
    /// right now), every 30 s once trusted: revoking is rare, and the
    /// notification above usually reports it sooner anyway.
    private func scheduleAccessibilityCheck() {
        accessibilityTimer?.invalidate()
        let interval: TimeInterval = wasTrusted ? 30 : 2
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkAccessibility()
        }
        timer.tolerance = interval / 4
        accessibilityTimer = timer
    }

    private func checkAccessibility() {
        let trusted = Permissions.isTrusted
        // Only assign on a change: every @Published write re-renders the
        // menu bar label and menu (~5 ms), even for an unchanged value.
        if accessibilityTrusted != trusted { accessibilityTrusted = trusted }
        guard trusted != wasTrusted else { return }
        wasTrusted = trusted
        if trusted {
            klog.notice("accessibility granted — relaunching")
            Self.relaunch()
        } else {
            klog.notice("accessibility revoked")
            scheduleAccessibilityCheck()   // back to fast polling for the re-grant
        }
    }

    private static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error {
                    klog.error("relaunch failed: \(error, privacy: .public)")
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func reloadPacks(bundled: URL = soundsDirectory(), added: URL = UserPacks.directory) {
        packs = Self.discoverPacks(bundled: bundled, added: added)
    }

    private static func discoverPacks(bundled: URL, added: URL) -> [SoundPack] {
        (SoundPack.discover(in: bundled) + SoundPack.discover(in: added))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Picks up sets added or removed outside ThockBox, e.g. one of yours
    /// deleted in Finder, which would otherwise stay listed and play
    /// nothing. Discovery takes ~2 ms, so it runs whenever the menu or
    /// Settings opens. If the playing set is gone, the one now current loads.
    func refreshPacks(bundled: URL = soundsDirectory(), added: URL = UserPacks.directory) {
        let found = Self.discoverPacks(bundled: bundled, added: added)
        // Only publish a real change: this runs as a menu opens, and any
        // change then makes SwiftUI rebuild the menu bar menu, which closes
        // it again (a plain click on the icon showed nothing).
        guard found.map(\.id) != packs.map(\.id) else { return }
        let playing = currentPack?.id
        packs = found
        if currentPack?.id != playing { applyPack(notify: false) }
    }

    /// Makes a switch set from the user's recordings and switches to it.
    func importSwitchSet(from sources: [URL]) throws {
        let id = try UserPacks.importPack(from: sources)
        reloadPacks()
        selectedPackID = id
    }

    func removeSwitchSet(_ pack: SoundPack) throws {
        guard UserPacks.isUserPack(pack) else { return }
        let wasSelected = currentPack?.id == pack.id
        try UserPacks.remove(pack)
        reloadPacks()
        if wasSelected { selectedPackID = "cream" }
    }

    /// What ThockBox is doing right now; the first thing that stops sound
    /// wins. The menu bar panel and the settings sidebar both show it.
    var status: PlaybackStatus {
        .from(trusted: accessibilityTrusted, enabled: enabled, offUntil: offUntil,
              shortcut: toggleShortcut.display,
              secureInputApp: secureInputApp, mute: automaticMute, pack: currentPack?.name ?? "")
    }

    /// The selected set, or Cream (the default) if it's gone, e.g. a set of
    /// yours deleted in Finder. The selection itself is kept, so the set
    /// comes back if it's restored.
    var currentPack: SoundPack? {
        packs.first { $0.id == selectedPackID } ?? packs.first { $0.id == "cream" } ?? packs.first
    }

    /// Changes the set from outside ThockBox's own controls (a Focus,
    /// Shortcuts, AppleScript), with a notification if the user asked for one.
    /// Returns whether a notification was posted.
    @discardableResult
    func selectPackFromElsewhere(_ id: String) -> Bool {
        guard id != selectedPackID else { return false }
        selectedPackID = id
        guard notifySetChanges else { return false }
        let name = packs.first { $0.id == id }?.name ?? id
        if postsNotifications { SetChangeNotifier.post(setName: name) }
        return true
    }

    private func applyPack(notify: Bool) {
        guard let pack = currentPack else {
            klog.error("no sound packs found")
            return
        }
        engine.load(pack: pack)
        klog.notice("loaded pack \(pack.id, privacy: .public)")
        if notify { playSwitchPreview() }
    }

    // MARK: - Preference previews (audible feedback for settings changes)

    private var volumePreview: DispatchWorkItem?

    /// The app icon in ThockBox's windows plays like a space bar.
    func pressAppIcon(down: Bool) {
        guard enabled, !isAutomaticallyMuted else { return }
        engine.playKey(keyClass: .space, up: !down, x: 0.5)
    }

    /// A short down/up pair so a new switch or volume can be judged instantly.
    func playSwitchPreview() {
        engine.playKey(keyClass: .row2, up: false, x: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.engine.playKey(keyClass: .row2, up: true, x: 0.5)
        }
    }

    /// Debounced so slider drags produce one preview, not a machine-gun burst.
    private func scheduleVolumePreview() {
        volumePreview?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.playSwitchPreview() }
        volumePreview = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    // MARK: - Event handling

    /// Releases not to play: the shortcut's key and the modifiers held with
    /// it, which would otherwise click with no matching press when sounds
    /// come on. Cleared by the next key press.
    private(set) var suppressedKeyUps: Set<UInt16> = []

    private func suppressReleasesAfterShortcut() {
        suppressedKeyUps = KeyMap.modifierKeycodes.subtracting([57]) // not Caps Lock
        suppressedKeyUps.insert(toggleShortcut.keyCode)
    }

    private var loggedFirstEvent = false

    /// Internal (not private) so the benchmark can feed it events.
    func handle(_ event: KeyListener.Event) {
        if !loggedFirstEvent {
            loggedFirstEvent = true
            klog.notice("first input event received — monitors are live")
        }
        switch event {
        case let .keyDown(keycode, isRepeat, flags):
            idleMode.recordActivity()
            if isAutomaticallyMuted { updateAutomaticMute() }
            // The shortcut (⌃⌘K by default) toggles, even while disabled.
            // Swallow the key-ups that follow too, or enabling would emit
            // orphan releases.
            if hotKey == nil, !isRepeat, !isRecordingShortcut,
               toggleShortcut.matches(keyCode: keycode, flags: flags) {
                enabled.toggle()
                suppressReleasesAfterShortcut()
                return
            }
            if !isRepeat { suppressedKeyUps.removeAll() }
            guard enabled, !isAutomaticallyMuted, !isRepeat, audible(keycode) else { return }
            // Sound first; stats and haptics can trail it.
            let info = KeyMap.info(for: keycode)
            let velocity = dynamics.press(keycode, at: ProcessInfo.processInfo.systemUptime)
            if returnDing, KeyMap.returnKeycodes.contains(keycode) {
                engine.playKey(keyClass: .enter, up: false, x: info.x, velocity: velocity)
                playDing()
            } else {
                engine.playKey(keyClass: info.keyClass, up: false, x: info.x, velocity: velocity)
            }
            if hapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            stats.record()
        case let .keyUp(keycode):
            if suppressedKeyUps.remove(keycode) != nil { return }
            guard enabled, !isAutomaticallyMuted, audible(keycode) else { return }
            let info = KeyMap.info(for: keycode)
            engine.playKey(keyClass: info.keyClass, up: true, x: info.x, velocity: dynamics.release(keycode))
        case .mouseDown:
            guard enabled, !isAutomaticallyMuted, mouseClicks else { return }
            engine.playExtra(named: "click_down", gain: 0.9)
        case .mouseUp:
            guard enabled, !isAutomaticallyMuted, mouseClicks else { return }
            engine.playExtra(named: "click_up", gain: 0.7)
        case let .scroll(delta, precise):
            guard enabled, !isAutomaticallyMuted, scrollSounds,
                  scrollTicker.scroll(delta: delta, precise: precise,
                                      at: ProcessInfo.processInfo.systemUptime) else { return }
            engine.playExtra(named: "click_up", gain: 0.3)
            if hapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        case .optionStatusItemClick:
            enabled.toggle()
        }
    }

    private func audible(_ keycode: UInt16) -> Bool {
        if muteModifiers && KeyMap.modifierKeycodes.contains(keycode) { return false }
        if !functionKeysAudible && KeyMap.functionKeycodes.contains(keycode) { return false }
        return true
    }

    private func playDing() {
        // The typewriter ding ships as a shared extra, outside any pack.
        engine.playExtra(named: "ding")
    }

    // MARK: - Stats

    func flushStats() {
        stats.flush()
    }

    // MARK: - System integration

    /// What the menu and the settings windows refresh when they open.
    func refreshOnOpen() {
        refreshAccessibilityStatus()
        refreshPacks()
        resumeIfDue()
        // Picks up "Open at login" changed in System Settings meanwhile.
        reconcileLoginItem()
    }

    func refreshAccessibilityStatus() {
        let trusted = Permissions.isTrusted
        if accessibilityTrusted != trusted { accessibilityTrusted = trusted }
        let holder = SecureInput.holder()
        if secureInputApp != holder { secureInputApp = holder }
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            klog.error("login item update failed: \(error, privacy: .public)")
            reconcileLoginItem()
        }
    }

    /// Keep the checkbox truthful: reflect the actual SMAppService status
    /// (registration can fail, or be changed in System Settings).
    func reconcileLoginItem() {
        let enabled = SMAppService.mainApp.status == .enabled
        // Only on a change: it also runs whenever the menu or Settings opens.
        guard launchAtLogin != enabled else { return }
        reconcilingLoginItem = true
        launchAtLogin = enabled
        reconcilingLoginItem = false
    }

    private var idleTimer: Timer?

    /// The idle check only needs to run while idle muting is on (it's off by
    /// default), so the app isn't woken every 5 seconds for nothing.
    private func updateIdleTimer() {
        guard idleTimeoutMinutes > 0 else {
            idleTimer?.invalidate()
            idleTimer = nil
            return
        }
        guard idleTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            self.updateAutomaticMute()
        }
        timer.tolerance = 5
        idleTimer = timer
    }

    /// Called from the screen lock/unlock notifications (and by tests).
    /// Screen capture has no notification, so it's checked every 2 s, and
    /// only while the setting is on.
    private func updateScreenShareWatch() {
        screenShareTimer?.invalidate()
        screenShareTimer = nil
        guard muteWhileSharing, ScreenCapture.isAvailable else {
            setScreenShared(false)
            return
        }
        setScreenShared(isScreenCaptured())
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            setScreenShared(isScreenCaptured())
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        screenShareTimer = timer
    }

    /// Internal so tests can set it.
    /// Always re-checks the mute, even when the value didn't change: turning
    /// the setting on while something is already capturing must mute.
    func setScreenShared(_ shared: Bool) {
        screenShared = shared
        updateAutomaticMute()
    }

    func setScreenLocked(_ locked: Bool) {
        screenLocked = locked
        updateAutomaticMute()
    }

    /// Called by the microphone monitor (and by tests).
    func setMicrophoneInUse(_ inUse: Bool) {
        microphoneInUse = inUse
        updateAutomaticMute()
    }

    /// Adds or removes an app from the muted list, never twice.
    func setMuted(_ muted: Bool, appID: String) {
        if muted {
            if !mutedApps.contains(appID) { mutedApps.append(appID) }
        } else {
            mutedApps.removeAll { $0 == appID }
        }
    }

    private func setFrontApp(_ app: NSRunningApplication?) {
        let category = app?.bundleURL.flatMap { Bundle(url: $0) }?
            .object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        setFrontApp(id: app?.bundleIdentifier, name: app?.localizedName,
                    isGame: FrontApp.isGame(category: category, path: app?.bundleURL?.path))
    }

    /// Called when another app comes to the front (and by tests).
    func setFrontApp(id: String?, name: String?, isGame: Bool = false) {
        guard id != Bundle.main.bundleIdentifier else { return }
        frontApp = id.map { FrontApp(id: $0, name: name ?? $0, isGame: isGame) }
        updateAutomaticMute()
    }

    private func updateMicrophoneMonitor() {
        guard muteDuringCalls else {
            microphoneMonitor = nil
            microphoneInUse = false
            return
        }
        guard microphoneMonitor == nil else { return }
        let monitor = AudioActivityMonitor(.recording) { [weak self] inUse in self?.setMicrophoneInUse(inUse) }
        microphoneMonitor = monitor
        microphoneInUse = monitor.inUse
    }

    private func updateMediaMonitor() {
        guard muteWhileMedia else {
            mediaMonitor = nil
            setMediaPlaying(false)
            return
        }
        guard mediaMonitor == nil else { return }
        let monitor = AudioActivityMonitor(.playing) { [weak self] playing in self?.setMediaPlaying(playing) }
        mediaMonitor = monitor
        setMediaPlaying(monitor.inUse)
    }

    /// Called by the media monitor (and by tests).
    func setMediaPlaying(_ playing: Bool) {
        mediaPlaying = playing
        updateAutomaticMute()
    }

    private func updateCalendarMonitor() {
        guard muteDuringMeetings else {
            calendarMonitor = nil
            setInCalendarEvent(false)
            return
        }
        guard calendarMonitor == nil, readsCalendars else { return }
        calendarMonitor = CalendarMonitor(
            ignoring: ignoredCalendarIDs,
            onChange: { [weak self] inEvent in self?.setInCalendarEvent(inEvent) },
            onAccess: { [weak self] access in self?.calendarAccess = access },
            onCalendars: { [weak self] calendars in
                if self?.calendars != calendars { self?.calendars = calendars }
            })
    }

    /// Called by the calendar monitor (and by tests).
    func setInCalendarEvent(_ inEvent: Bool) {
        inCalendarEvent = inEvent
        updateAutomaticMute()
    }

    /// `now` is a parameter so tests can check the idle timeout without waiting.
    func updateAutomaticMute(now: Date = Date()) {
        let reason: AutomaticMute?
        if muteDuringCalls && microphoneInUse {
            reason = .call
        } else if muteDuringMeetings && inCalendarEvent {
            reason = .meeting
        } else if muteWhenLocked && screenLocked {
            reason = .screenLocked
        } else if muteWhileSharing && screenShared {
            reason = .screenShared
        } else if muteWhileMedia && mediaPlaying {
            reason = .media
        } else if headphonesOnly && outputIsSpeaker {
            reason = .speakers
        } else if let frontApp, mutedApps.contains(frontApp.id) {
            reason = .app(frontApp.name)
        } else if muteWhileGaming, let frontApp, frontApp.isGame {
            reason = .game(frontApp.name)
        } else if idleMode.isIdle(at: now, timeoutMinutes: idleTimeoutMinutes) {
            reason = .idle
        } else {
            reason = nil
        }
        guard reason != automaticMute else { return }
        let wasMuted = isAutomaticallyMuted
        automaticMute = reason
        if wasMuted != isAutomaticallyMuted { syncEngineState() }
    }

    private func syncEngineState() {
        guard enabled, !isAutomaticallyMuted else {
            engine.stop()
            return
        }
        do {
            try engine.start()
            // Only pin an output device when one is explicitly saved; default
            // routing follows the system output on its own.
            if outputDeviceUID != nil || outputChangedWhileDisabled {
                applyOutputDevice()
            }
        } catch {
            klog.error("engine start failed: \(error, privacy: .public)")
        }
    }

    /// The device sound actually goes to: the picked one while it's
    /// connected, otherwise the system default.
    private func outputRouteChanged() {
        let devices = AudioDevices.outputDevices()
        let picked = devices.first { $0.uid == outputDeviceUID }
        // A picked device that was unplugged and comes back gets the sound
        // again; one that just left hands it to the default right away.
        if Self.needsReapply(target: picked?.id ?? AudioDevices.defaultOutputDevice(),
                             applied: appliedOutputDevice) {
            applyOutputDevice()
        }
        let current = picked ?? devices.first { $0.id == AudioDevices.defaultOutputDevice() }
        setActiveOutput(uid: current?.uid)
        if let current {
            dataSourceListener = SystemAudioListener.dataSource(of: current.id) { [weak self] in
                self?.outputRouteChanged()
            }
            setOutputIsSpeaker(AudioDevices.isSpeaker(current.id))
        }
    }

    /// Called when the output changes (and by tests).
    func setOutputIsSpeaker(_ isSpeaker: Bool) {
        outputIsSpeaker = isSpeaker
        updateAutomaticMute()
    }

    /// Switches to `uid`'s saved volume, or saves the current volume for a
    /// device seen for the first time. Internal so tests can call it.
    func setActiveOutput(uid: String?) {
        guard let uid, uid != activeOutputUID else { return }
        activeOutputUID = uid
        restoringVolume = true
        volume = volumeByDevice[uid] ?? volume
        restoringVolume = false
    }

    private func applyOutputDevice() {
        guard enabled, !isAutomaticallyMuted else {
            outputChangedWhileDisabled = true
            return
        }
        outputChangedWhileDisabled = false
        let picked = AudioDevices.id(forUID: outputDeviceUID, in: AudioDevices.outputDevices())
        // setOutputDevice(nil) pins the engine to the default as it is now,
        // so remember that device, not "default".
        appliedOutputDevice = picked ?? AudioDevices.defaultOutputDevice()
        engine.setOutputDevice(picked)
    }

    /// The device the engine was last pointed at.
    private var appliedOutputDevice: AudioDeviceID?

    /// Whether the engine should be pointed again after the device list or
    /// default changes: when where it should play now (the picked device,
    /// or the default when none is picked or it's unplugged) differs from
    /// where it was sent. Pointing the engine pins a device, so this also
    /// keeps System Default following the default.
    static func needsReapply(target: AudioDeviceID, applied: AudioDeviceID?) -> Bool {
        target != applied
    }


    /// Sounds live in the app bundle's Resources/Sounds; during `swift run`
    /// development, fall back to ./Resources/Sounds in the working directory.
    static func soundsDirectory() -> URL {
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("Sounds")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Sounds")
    }
}

import AppKit
import Carbon.HIToolbox
import Combine
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
            syncEngineState()
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
    @Published var hapticFeedback: Bool {
        didSet { defaults.set(hapticFeedback, forKey: "hapticFeedback") }
    }
    /// Hidden, ThockBox keeps running; opening it again from Finder or
    /// Spotlight shows the settings window. macOS also turns this off when
    /// the icon is ⌘-dragged out of the menu bar.
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            guard !reconcilingLoginItem else { return }
            updateLoginItem()
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
        didSet { defaults.set(try? JSONEncoder().encode(toggleShortcut), forKey: "toggleShortcut") }
    }
    /// Set while Settings records a new shortcut, so pressing the current
    /// one there doesn't also toggle sounds.
    var isRecordingShortcut = false
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
            outputRouteChanged()
            applyOutputDevice()
        }
    }
    /// A picker change made while sounds are off or automatically muted is
    /// applied on resume; otherwise System Default could keep the old device.
    private var outputChangedWhileDisabled = false

    // MARK: - Stats

    let stats: StatsStore

    @Published private(set) var accessibilityTrusted = Permissions.isTrusted
    /// Checked when the menu or settings window opens; see secureInputHolder().
    @Published private(set) var secureInputApp: String?
    /// Why sounds are automatically muted right now, if they are.
    @Published private(set) var automaticMute: AutomaticMute?
    var isAutomaticallyMuted: Bool { automaticMute != nil }
    /// Another app is recording (only tracked while muteDuringCalls is on).
    @Published private(set) var microphoneInUse = false

    private let defaults: UserDefaults
    private var idleMode = IdleMode()
    private var screenLocked = false
    private var microphoneMonitor: MicrophoneMonitor?
    /// Each output device keeps its own volume, as macOS does for system
    /// volume: headphones usually want less than speakers.
    private var volumeByDevice: [String: Float]
    private(set) var activeOutputUID: String?
    private var restoringVolume = false
    private var outputListeners: [SystemAudioListener] = []
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
            "hapticFeedback": false,
            "launchAtLogin": false, "showMenuBarIcon": true, "muteWhenLocked": false, "muteDuringCalls": false,
            "idleTimeoutMinutes": 0,
        ])
        enabled = defaults.bool(forKey: "enabled")
        volume = min(max(defaults.float(forKey: "volume"), 0), 1)
        selectedPackID = defaults.string(forKey: "pack") ?? "cream"
        toneX = min(max(defaults.float(forKey: "toneX"), -1), 1)
        toneY = min(max(defaults.float(forKey: "toneY"), -1), 1)
        pitchVariation = min(max(defaults.float(forKey: "pitchVariation"), 0), 150)
        muteModifiers = defaults.bool(forKey: "muteModifiers")
        functionKeysAudible = defaults.bool(forKey: "functionKeysAudible")
        returnDing = defaults.bool(forKey: "returnDing")
        mouseClicks = defaults.bool(forKey: "mouseClicks")
        hapticFeedback = defaults.bool(forKey: "hapticFeedback")
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        muteWhenLocked = defaults.bool(forKey: "muteWhenLocked")
        muteDuringCalls = defaults.bool(forKey: "muteDuringCalls")
        mutedApps = defaults.stringArray(forKey: "mutedApps") ?? []
        toggleShortcut = defaults.data(forKey: "toggleShortcut")
            .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .standard
        idleTimeoutMinutes = max(0, defaults.integer(forKey: "idleTimeoutMinutes"))
        outputDeviceUID = defaults.string(forKey: "outputDeviceUID")
        volumeByDevice = defaults.dictionary(forKey: "volumeByDevice") as? [String: Float] ?? [:]
        stats = StatsStore(defaults: defaults)
    }

    // MARK: - Lifecycle

    func startUp() {
        reloadPacks()
        engine.volume = volume
        engine.pitchVariationCents = pitchVariation
        engine.setTone(x: toneX, y: toneY)
        applyPack(notify: false)
        engine.loadExtras(from: Self.soundsDirectory().appendingPathComponent("_extras"))
        if let session = CGSessionCopyCurrentDictionary() as NSDictionary? {
            screenLocked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        }
        updateMicrophoneMonitor()
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
        listener.handler = { [weak self] event in
            self?.handle(event)
        }
        accessibilityTrusted = Permissions.requestIfNeeded()
        listener.listensToMouse = mouseClicks
        listener.start()
        reconcileLoginItem()
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.stats.rollOver()
        }
        klog.notice("startup: trusted=\(self.accessibilityTrusted, privacy: .public) packs=\(self.packs.count, privacy: .public) device=\(self.outputDeviceUID ?? "default", privacy: .public)")

        // Monitors registered without Accessibility access don't recover
        // in-process. Watch both directions so a revoked then restored grant
        // gets the same fresh process as a grant made on first launch.
        wasTrusted = accessibilityTrusted
        scheduleAccessibilityCheck()
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

    func reloadPacks() {
        packs = (SoundPack.discover(in: Self.soundsDirectory()) + SoundPack.discover(in: UserPacks.directory))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
        .from(trusted: accessibilityTrusted, enabled: enabled, shortcut: toggleShortcut.display,
              secureInputApp: secureInputApp, mute: automaticMute, pack: currentPack?.name ?? "")
    }

    var currentPack: SoundPack? {
        packs.first { $0.id == selectedPackID } ?? packs.first
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

    private var suppressNextKeyUp: UInt16?

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
            // Swallow the matching key-up too, or enabling would emit an
            // orphan release.
            if !isRepeat, !isRecordingShortcut, toggleShortcut.matches(keyCode: keycode, flags: flags) {
                enabled.toggle()
                suppressNextKeyUp = keycode
                return
            }
            guard enabled, !isAutomaticallyMuted, !isRepeat, audible(keycode) else { return }
            // Sound first; stats and haptics can trail it.
            let info = KeyMap.info(for: keycode)
            if returnDing, KeyMap.returnKeycodes.contains(keycode) {
                engine.playKey(keyClass: .enter, up: false, x: info.x)
                playDing()
            } else {
                engine.playKey(keyClass: info.keyClass, up: false, x: info.x)
            }
            if hapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            stats.record()
        case let .keyUp(keycode):
            if keycode == suppressNextKeyUp {
                suppressNextKeyUp = nil
                return
            }
            guard enabled, !isAutomaticallyMuted, audible(keycode) else { return }
            let info = KeyMap.info(for: keycode)
            engine.playKey(keyClass: info.keyClass, up: true, x: info.x)
        case .mouseDown:
            guard enabled, !isAutomaticallyMuted, mouseClicks else { return }
            engine.playExtra(named: "click_down", gain: 0.9)
        case .mouseUp:
            guard enabled, !isAutomaticallyMuted, mouseClicks else { return }
            engine.playExtra(named: "click_up", gain: 0.7)
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

    func refreshAccessibilityStatus() {
        let trusted = Permissions.isTrusted
        if accessibilityTrusted != trusted { accessibilityTrusted = trusted }
        let holder = Self.secureInputHolder()
        if secureInputApp != holder { secureInputApp = holder }
    }

    /// The app holding Secure Input, if any. While it's on (a focused
    /// password field, Terminal's Secure Keyboard Entry, or an app that
    /// forgot to turn it off), macOS sends no key events to other apps, so
    /// sounds stop with no other sign.
    static func secureInputHolder() -> String? {
        guard IsSecureEventInputEnabled() else { return nil }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let app = (session?["kCGSSessionSecureInputPID"] as? Int)
            .flatMap { NSRunningApplication(processIdentifier: pid_t($0)) }
        return secureInputHolderName(bundleID: app?.bundleIdentifier, name: app?.localizedName)
    }

    /// The lock screen always holds Secure Input; that's covered by the
    /// screen-lock mute, so it isn't reported.
    static func secureInputHolderName(bundleID: String?, name: String?) -> String? {
        guard bundleID != "com.apple.loginwindow" else { return nil }
        return name ?? "Another app"
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
        reconcilingLoginItem = true
        launchAtLogin = SMAppService.mainApp.status == .enabled
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
        setFrontApp(id: app?.bundleIdentifier, name: app?.localizedName)
    }

    /// Called when another app comes to the front (and by tests).
    func setFrontApp(id: String?, name: String?) {
        guard id != Bundle.main.bundleIdentifier else { return }
        frontApp = id.map { FrontApp(id: $0, name: name ?? $0) }
        updateAutomaticMute()
    }

    private func updateMicrophoneMonitor() {
        guard muteDuringCalls else {
            microphoneMonitor = nil
            microphoneInUse = false
            return
        }
        guard microphoneMonitor == nil else { return }
        let monitor = MicrophoneMonitor { [weak self] inUse in self?.setMicrophoneInUse(inUse) }
        microphoneMonitor = monitor
        microphoneInUse = monitor.inUse
    }

    /// `now` is a parameter so tests can check the idle timeout without waiting.
    func updateAutomaticMute(now: Date = Date()) {
        let reason: AutomaticMute?
        if muteDuringCalls && microphoneInUse {
            reason = .call
        } else if muteWhenLocked && screenLocked {
            reason = .screenLocked
        } else if let frontApp, mutedApps.contains(frontApp.id) {
            reason = .app(frontApp.name)
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
        let current = picked ?? devices.first { $0.id == AudioDevices.defaultOutputDevice() }
        setActiveOutput(uid: current?.uid)
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
        engine.setOutputDevice(AudioDevices.id(forUID: outputDeviceUID, in: AudioDevices.outputDevices()))
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

struct FrontApp: Equatable {
    let id: String
    let name: String
}

/// The reasons sounds can be muted without the user turning them off.
enum AutomaticMute: Equatable {
    case call
    case screenLocked
    case app(String)
    case idle

    var message: String {
        switch self {
        case .call: "Muted while another app uses the microphone."
        case .screenLocked: "Muted while the screen is locked."
        case .app(let name): "Muted in \(name)."
        case .idle: "Muted after inactivity. Press any key to wake it."
        }
    }

    var symbol: String {
        switch self {
        case .call: "mic.fill"
        case .screenLocked: "lock.fill"
        case .app: "speaker.slash.fill"
        case .idle: "moon.zzz.fill"
        }
    }
}

/// The one status line shown in the menu bar panel and the settings
/// sidebar, so both always agree on what's happening and why.
enum PlaybackStatus: Equatable {
    case needsAccess
    case off(shortcut: String)
    case blocked(app: String)
    case muted(AutomaticMute)
    case playing(pack: String)

    static func from(trusted: Bool, enabled: Bool, shortcut: String, secureInputApp: String?,
                     mute: AutomaticMute?, pack: String) -> PlaybackStatus {
        if !trusted { return .needsAccess }
        if !enabled { return .off(shortcut: shortcut) }
        if let app = secureInputApp { return .blocked(app: app) }
        if let mute { return .muted(mute) }
        return .playing(pack: pack)
    }

    var title: String {
        switch self {
        case .needsAccess: "Needs Accessibility access"
        case .off: "Off"
        case .blocked(let app): "Paused by \(app)"
        case .muted(.call): "Muted during a call"
        case .muted(.screenLocked): "Muted while locked"
        case .muted(.app(let name)): "Muted in \(name)"
        case .muted(.idle): "Muted after inactivity"
        case .playing(let pack): "Playing \(pack)"
        }
    }

    /// One sentence of explanation, when the title alone isn't enough.
    var detail: String? {
        switch self {
        case .needsAccess:
            "Allow ThockBox in System Settings so it can hear key presses. Nothing you type leaves your Mac."
        case .off(let shortcut):
            "Turn it on here or with \(shortcut)."
        case .blocked(let app):
            "\(app) has secure input on, which hides key presses from other apps. That's normal in a password field. If it lasts, quit and reopen \(app)."
        case .muted(.idle):
            "Press any key to wake it."
        case .muted, .playing:
            nil
        }
    }

    var symbol: String {
        switch self {
        case .needsAccess: "exclamationmark.triangle.fill"
        case .off: "speaker.slash.fill"
        case .blocked: "lock.shield.fill"
        case .muted(let reason): reason.symbol
        case .playing: "speaker.wave.2.fill"
        }
    }

    /// Something the user has to act on, not a choice they made.
    var needsAttention: Bool {
        switch self {
        case .needsAccess, .blocked: true
        default: false
        }
    }
}

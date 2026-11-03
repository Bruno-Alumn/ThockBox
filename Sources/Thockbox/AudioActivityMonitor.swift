import CoreAudio
import Foundation

/// Reports whether another app is recording from a microphone, as during a
/// call, or playing audio, as with music or a video. Event-driven: CoreAudio
/// calls back when a process starts or stops, so nothing polls. Only reads
/// CoreAudio state; it never opens an input itself, so it doesn't trigger
/// the microphone indicator.
///
/// Needs macOS 14.2, which reports input and output per process. Older
/// versions only say whether a device is running at all, which ThockBox's
/// own sound (and "Hey Siri") would trip, so there it always reports false.
final class AudioActivityMonitor {
    enum Activity {
        /// Another app records from a microphone: a call or a recording.
        case recording
        /// Another app plays sound: music, a video, a game.
        case playing
    }

    static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    /// System services that listen all the time ("Hey Siri", Voice
    /// Control). Their input isn't a call.
    static let alwaysListening: Set<String> = [
        "com.apple.CoreSpeech", "com.apple.assistantd", "com.apple.siri",
        "com.apple.VoiceControl", "com.apple.speech.VoiceControl",
    ]

    /// System services that play short sounds or speech on their own
    /// (alerts, the power chime, VoiceOver). They aren't media.
    static let systemSounds: Set<String> = [
        "systemsoundserverd", "com.apple.PowerChime", "com.apple.VoiceOver",
        "com.apple.speech.speechsynthesisd", "com.apple.accessibility.heard",
    ]

    let activity: Activity
    /// The other apps doing it now, by bundle ID ("process:<name>" for a
    /// process without one), so the user can see and ignore them.
    private(set) var apps: Set<String> = []
    var inUse: Bool { !apps.isEmpty }
    private let onChange: (Set<String>) -> Void
    private var watched: [(AudioObjectID, AudioObjectPropertyAddress)] = []
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.rewatch()
    }

    init(_ activity: Activity, onChange: @escaping (Set<String>) -> Void) {
        self.activity = activity
        self.onChange = onChange
        rewatch()
    }

    deinit {
        unwatchAll()
    }

    /// Re-registers listeners for the current set of audio processes (or the
    /// current default input device), then re-reads the state.
    private func rewatch() {
        unwatchAll()
        if #available(macOS 14.2, *) {
            // Any process starting or stopping audio changes this list; each
            // process then reports its own input or output state.
            let system = AudioObjectID(kAudioObjectSystemObject)
            watch(system, kAudioHardwarePropertyProcessObjectList)
            for process in Self.objects(system, kAudioHardwarePropertyProcessObjectList) {
                watch(process, Self.selector(activity))
            }
        }
        let now = Self.others(activity)
        guard now != apps else { return }
        apps = now
        onChange(now)
    }

    private func watch(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) {
        guard object != kAudioObjectUnknown else { return }
        var address = Self.address(selector)
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, listener) == noErr {
            watched.append((object, address))
        }
    }

    private func unwatchAll() {
        for (object, address) in watched {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, listener)
        }
        watched.removeAll()
    }

    @available(macOS 14.2, *)
    private static func selector(_ activity: Activity) -> AudioObjectPropertySelector {
        switch activity {
        case .recording: kAudioProcessPropertyIsRunningInput
        case .playing: kAudioProcessPropertyIsRunningOutput
        }
    }

    static func someoneElseIs(_ activity: Activity) -> Bool {
        !others(activity).isEmpty
    }

    /// Bundle IDs of the other apps recording or playing right now.
    static func others(_ activity: Activity) -> Set<String> {
        guard #available(macOS 14.2, *) else { return [] }
        let me = getpid()
        var found: Set<String> = []
        for process in objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) {
            let running: UInt32 = value(process, selector(activity)) ?? 0
            guard running != 0 else { continue }
            let pid: pid_t = value(process, kAudioProcessPropertyPID) ?? me
            let id = bundleID(process)
            let counts = switch activity {
            case .recording: countsAsCall(recording: true, pid: pid, ownPID: me, bundleID: id)
            case .playing: countsAsMedia(playing: true, pid: pid, ownPID: me, bundleID: id)
            }
            if counts { found.insert(id ?? Self.processKey(pid)) }
        }
        return found
    }

    /// Whether one audio process means a call or recording: it's taking
    /// input, it isn't ThockBox, and it isn't a system service that listens
    /// all the time. The bundle ID is looked up last, only when needed.
    static func countsAsCall(recording: Bool, pid: pid_t, ownPID: pid_t,
                             bundleID: @autoclosure () -> String?) -> Bool {
        recording && pid != ownPID && !alwaysListening.contains(bundleID() ?? "")
    }

    /// Whether one audio process means media is playing: it's sending
    /// sound out, it isn't ThockBox, and it isn't a system alert or voice.
    static func countsAsMedia(playing: Bool, pid: pid_t, ownPID: pid_t,
                              bundleID: @autoclosure () -> String?) -> Bool {
        guard playing, pid != ownPID else { return false }
        // The "Hey Siri" and Voice Control services keep output open too.
        let id = bundleID() ?? ""
        return !systemSounds.contains(id) && !alwaysListening.contains(id)
    }

    /// Stands in for a bundle ID for a process without one (a command-line
    /// player, an audio daemon), so it can still be named and ignored.
    static let processPrefix = "process:"

    static func processKey(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        // Without a readable name it's still listed (and can be ignored).
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return processPrefix + "process \(pid)" }
        return processPrefix + String(cString: buffer)
    }

    @available(macOS 14.2, *)
    private static func bundleID(_ process: AudioObjectID) -> String? {
        var address = address(kAudioProcessPropertyBundleID)
        var id: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &id) == noErr,
              let id else { return nil }
        return id.takeRetainedValue() as String
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, result) == noErr else { return nil }
        return result.pointee
    }

    private static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }
}

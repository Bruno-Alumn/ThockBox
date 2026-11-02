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
    private(set) var inUse = false
    private let onChange: (Bool) -> Void
    private var watched: [(AudioObjectID, AudioObjectPropertyAddress)] = []
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.rewatch()
    }

    init(_ activity: Activity, onChange: @escaping (Bool) -> Void) {
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
        let now = Self.someoneElseIs(activity)
        guard now != inUse else { return }
        inUse = now
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
        guard #available(macOS 14.2, *) else { return false }
        let me = getpid()
        return objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
            .contains { process in
                let running: UInt32 = value(process, selector(activity)) ?? 0
                let pid: pid_t = value(process, kAudioProcessPropertyPID) ?? me
                switch activity {
                case .recording:
                    return countsAsCall(recording: running != 0, pid: pid, ownPID: me,
                                        bundleID: bundleID(process))
                case .playing:
                    return countsAsMedia(playing: running != 0, pid: pid, ownPID: me,
                                         bundleID: bundleID(process))
                }
            }
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
        playing && pid != ownPID && !systemSounds.contains(bundleID() ?? "")
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

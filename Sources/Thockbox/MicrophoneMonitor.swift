import CoreAudio
import Foundation

/// Reports whether another app is recording from a microphone, as during a
/// call. Event-driven: CoreAudio calls back when recording starts or stops,
/// so nothing polls. Only reads CoreAudio state; it never opens an input
/// itself, so it doesn't trigger the microphone indicator.
///
/// Needs macOS 14.2, which reports input per process. Older versions only
/// say whether the microphone is running at all, and "Hey Siri" keeps it
/// running, so there the monitor always reports false.
final class MicrophoneMonitor {
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

    private(set) var inUse = false
    private let onChange: (Bool) -> Void
    private var watched: [(AudioObjectID, AudioObjectPropertyAddress)] = []
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.rewatch()
    }

    init(onChange: @escaping (Bool) -> Void) {
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
            // process then reports its own input state.
            let system = AudioObjectID(kAudioObjectSystemObject)
            watch(system, kAudioHardwarePropertyProcessObjectList)
            for process in Self.objects(system, kAudioHardwarePropertyProcessObjectList) {
                watch(process, kAudioProcessPropertyIsRunningInput)
            }
        }
        let now = Self.someoneElseIsRecording()
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

    static func someoneElseIsRecording() -> Bool {
        guard #available(macOS 14.2, *) else { return false }
        let me = getpid()
        return objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
            .contains { process in
                let recording: UInt32 = value(process, kAudioProcessPropertyIsRunningInput) ?? 0
                let pid: pid_t = value(process, kAudioProcessPropertyPID) ?? me
                return countsAsCall(recording: recording != 0, pid: pid, ownPID: me,
                                    bundleID: bundleID(process))
            }
    }

    /// Whether one audio process means a call or recording: it's taking
    /// input, it isn't ThockBox, and it isn't a system service that listens
    /// all the time. The bundle ID is looked up last, only when needed.
    static func countsAsCall(recording: Bool, pid: pid_t, ownPID: pid_t,
                             bundleID: @autoclosure () -> String?) -> Bool {
        recording && pid != ownPID && !alwaysListening.contains(bundleID() ?? "")
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

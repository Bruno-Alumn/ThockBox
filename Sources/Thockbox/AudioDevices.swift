import CoreAudio
import Foundation

/// Minimal CoreAudio output-device enumeration for the output picker.
enum AudioDevices {
    struct Device: Identifiable, Hashable {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    static func outputDevices() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard outputChannelCount(id) > 0,
                  let name = stringProperty(id, kAudioObjectPropertyName),
                  let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return Device(id: id, uid: uid, name: name)
        }
    }

    /// The device to use for a saved UID. nil (system default) when nothing
    /// is saved or the saved device isn't connected right now.
    static func id(forUID uid: String?, in devices: [Device]) -> AudioDeviceID? {
        guard let uid else { return nil }
        return devices.first { $0.uid == uid }?.id
    }

    /// Whether sound from this device fills the room rather than going into
    /// someone's ears: the Mac's own speakers, a display, or AirPlay.
    static func isSpeaker(_ id: AudioDeviceID) -> Bool {
        isSpeaker(transport: uint32(id, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal),
                  dataSource: uint32(id, kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput))
    }

    /// Built-in output is speakers unless it reports the headphone jack
    /// ('hdpn'); unsure, it counts as speakers, since the point is not to
    /// play out loud. Bluetooth, USB and the rest count as headphones.
    static func isSpeaker(transport: UInt32?, dataSource: UInt32?) -> Bool {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return dataSource != headphoneDataSource
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeAirPlay:
            return true
        default:
            return false
        }
    }

    static let headphoneDataSource: UInt32 = 0x6864_706E // 'hdpn'

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               _ scope: AudioObjectPropertyScope) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func defaultOutputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                   &address, 0, nil, &size, &id)
        return id
    }

    private static func outputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size > 0 else { return 0 }
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr) == noErr else { return 0 }
        let list = ptr.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func stringProperty(_ id: AudioObjectID,
                               _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

/// Calls back on the main queue when an audio property changes, such as
/// the default output device, until it's released.
///
/// Uses the function-pointer listener API: CoreAudio never removed a Swift
/// closure passed as a listener block (it doesn't see the same block twice),
/// so block listeners piled up and kept firing.
final class SystemAudioListener {
    /// What CoreAudio holds on to. It outlives the listener briefly, since a
    /// callback may already be on its way when the listener is removed.
    private final class Target {
        var onChange: (() -> Void)?
        init(_ onChange: @escaping () -> Void) { self.onChange = onChange }
    }

    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let target: Target
    private let context: UnsafeMutableRawPointer
    private let added: Bool

    init(_ selector: AudioObjectPropertySelector, on object: AudioObjectID = AudioObjectID(kAudioObjectSystemObject),
         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, onChange: @escaping () -> Void) {
        self.object = object
        address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                             mElement: kAudioObjectPropertyElementMain)
        target = Target(onChange)
        context = Unmanaged.passRetained(target).toOpaque()
        added = AudioObjectAddPropertyListener(object, &address, Self.callback, context) == noErr
    }

    deinit {
        target.onChange = nil
        if added {
            AudioObjectRemovePropertyListener(object, &address, Self.callback, context)
        }
        let context = context
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Unmanaged<Target>.fromOpaque(context).release()
        }
    }

    private static let callback: AudioObjectPropertyListenerProc = { _, _, _, context in
        guard let context else { return noErr }
        let target = Unmanaged<Target>.fromOpaque(context).takeUnretainedValue()
        DispatchQueue.main.async { target.onChange?() }
        return noErr
    }

    /// Fires when a device switches between speakers and the headphone jack
    /// (older Macs use one device for both).
    static func dataSource(of device: AudioDeviceID, onChange: @escaping () -> Void) -> SystemAudioListener {
        SystemAudioListener(kAudioDevicePropertyDataSource, on: device,
                            scope: kAudioDevicePropertyScopeOutput, onChange: onChange)
    }

    /// Fires when a device is connected or disconnected.
    static func devices(onChange: @escaping () -> Void) -> SystemAudioListener {
        SystemAudioListener(kAudioHardwarePropertyDevices, onChange: onChange)
    }

    /// Fires when the default output changes or a device comes or goes.
    static func outputRoute(onChange: @escaping () -> Void) -> [SystemAudioListener] {
        [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices].map {
            SystemAudioListener($0, onChange: onChange)
        }
    }
}

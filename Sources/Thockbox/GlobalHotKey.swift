import AppKit
import Carbon.HIToolbox

/// The on/off shortcut as a system hotkey (RegisterEventHotKey), the
/// standard way for a Mac app to own a key combination everywhere: macOS
/// hands it to ThockBox alone, so the app in front never sees ⌃⌘K, and it
/// works without Accessibility access.
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// nil if macOS refuses the combination (another app already owns it).
    init?(_ shortcut: Shortcut, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, me, &handler)
        let id = EventHotKeyID(signature: OSType(0x54686B62), id: 1) // "Thkb"
        guard installed == noErr,
              RegisterEventHotKey(UInt32(shortcut.keyCode), Self.carbonModifiers(shortcut.flags), id,
                                  GetApplicationEventTarget(), 0, &ref) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods = 0
        if flags.contains(.command) { mods |= cmdKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.shift) { mods |= shiftKey }
        return UInt32(mods)
    }
}

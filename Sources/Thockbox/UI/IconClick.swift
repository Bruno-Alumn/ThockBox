import AppKit

/// What a plain click on the menu bar icon does. Control-click always opens
/// the menu, so it's never out of reach; Option-click toggles sounds either
/// way (see KeyListener).
enum IconClickAction: String, CaseIterable, Identifiable {
    case openMenu
    case toggleSounds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openMenu: "Opens the menu"
        case .toggleSounds: "Turns sounds on or off"
        }
    }

    /// Whether a click with these modifiers should toggle instead of
    /// opening the menu.
    func toggles(with modifiers: NSEvent.ModifierFlags) -> Bool {
        self == .toggleSounds
            && modifiers.intersection([.control, .option, .command, .shift]).isEmpty
    }
}

/// Catches clicks on ThockBox's own menu bar item before the menu opens.
/// SwiftUI's MenuBarExtra has no click handler of its own; its item lives in
/// an NSStatusBarWindow, and a local monitor sees that window's events first.
@MainActor
enum IconClick {
    private static var monitor: Any?

    static func install(state: AppState) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak state] event in
            guard let state, let window = event.window,
                  String(describing: type(of: window)).contains("StatusBarWindow"),
                  state.iconClickAction.toggles(with: event.modifierFlags) else { return event }
            state.enabled.toggle()
            return nil
        }
    }
}

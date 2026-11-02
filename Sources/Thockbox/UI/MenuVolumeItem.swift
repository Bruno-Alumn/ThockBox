import AppKit

/// A volume slider in the menu bar menu, like the one in the system Sound
/// menu. SwiftUI menus can't hold a slider, so it's an AppKit menu item put
/// under the menu's "Volume" heading each time the menu opens.
///
/// Dragging sets the engine's volume right away but saves it only when the
/// menu closes: saving publishes a change, and any change while the menu is
/// open makes SwiftUI rebuild the menu, which closes it.
@MainActor
final class MenuVolumeItem: NSObject {
    static let shared = MenuVolumeItem()

    /// The SwiftUI menu item the slider goes under.
    static let heading = "Volume"

    private let item = NSMenuItem()
    private let slider = NSSlider(value: 0.55, minValue: 0, maxValue: 1, target: nil, action: nil)
    private weak var state: AppState?
    private var unsaved: Float?
    /// Where the knob was, for a trackpad tap at each 10% (as in Settings).
    private var lastValue: Double = 0.55

    func install(state: AppState) {
        self.state = state
        slider.target = self
        slider.action = #selector(slid(_:))
        slider.isContinuous = true
        slider.controlSize = .small
        slider.setAccessibilityLabel("Volume")
        // The usual menu inset, so the slider lines up with the item titles.
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        slider.frame = NSRect(x: 18, y: 3, width: 184, height: 20)
        slider.autoresizingMask = [.width]
        view.addSubview(slider)
        item.view = view

        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] note in
            let menu = note.object as? NSMenu
            MainActor.assumeIsolated { self?.opened(menu) }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] note in
            let menu = note.object as? NSMenu
            MainActor.assumeIsolated { self?.closed(menu) }
        }
    }

    private func opened(_ menu: NSMenu?) {
        guard let menu, let state,
              let heading = menu.items.firstIndex(where: { $0.title == Self.heading && $0 !== item })
        else { return }
        slider.floatValue = state.volume
        lastValue = slider.doubleValue
        slider.isEnabled = state.enabled
        if item.menu !== menu {
            item.menu?.removeItem(item)
            menu.insertItem(item, at: heading + 1)
        }
    }

    @objc private func slid(_ sender: NSSlider) {
        if SliderDetents.crossed(from: lastValue, to: sender.doubleValue, in: 0...1, step: 0.1) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        lastValue = sender.doubleValue
        unsaved = sender.floatValue
        state?.engine.volume = sender.floatValue
        // Play a sample once the knob is let go, so the new level can be heard.
        if NSApp.currentEvent?.type == .leftMouseUp { state?.playSwitchPreview() }
    }

    private func closed(_ menu: NSMenu?) {
        guard let menu, item.menu === menu, let value = unsaved else { return }
        unsaved = nil
        state?.volume = value
    }
}

import AppKit

/// Calls back when one of the app's menus opens, and again once its items
/// are in. Since macOS 27, SwiftUI fills a menu bar menu only after it starts
/// tracking, so at that moment the menu is still empty.
@MainActor
final class MenuOpening: NSObject {
    private static let shared = MenuOpening()

    private var handlers: [(NSMenu) -> Void] = []
    /// The open menu, while it's open.
    private weak var menu: NSMenu?

    static func observe(_ handler: @escaping (NSMenu) -> Void) {
        shared.startObserving()
        shared.handlers.append(handler)
    }

    private var observing = false

    private func startObserving() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(began(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(added(_:)), name: NSMenu.didAddItemNotification, object: nil)
        center.addObserver(self, selector: #selector(ended(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
    }

    @objc private func began(_ note: Notification) {
        guard let menu = note.object as? NSMenu else { return }
        self.menu = menu
        notify()
    }

    /// Items arrive one at a time; call back once after each batch.
    @objc private func added(_ note: Notification) {
        guard let menu, note.object as? NSMenu === menu else { return }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(notify), object: nil)
        perform(#selector(notify), with: nil, afterDelay: 0, inModes: [.common, .eventTracking])
    }

    @objc private func ended(_ note: Notification) {
        if note.object as? NSMenu === menu { menu = nil }
    }

    @objc private func notify() {
        guard let menu else { return }
        for handler in handlers { handler(menu) }
        Self.dimEmptySubmenus(in: menu)
    }

    /// SwiftUI disables a submenu's items but not the item that opens it, so
    /// with sounds off "Turn Off For" looked usable and opened a list of
    /// gray choices. Gray it out too, as a Mac menu would.
    static func dimEmptySubmenus(in menu: NSMenu) {
        for item in menu.items {
            guard let submenu = item.submenu, !submenu.items.isEmpty else { continue }
            let usable = submenu.items.contains { $0.isEnabled && !$0.isSeparatorItem }
            if item.isEnabled != usable { item.isEnabled = usable }
        }
    }
}

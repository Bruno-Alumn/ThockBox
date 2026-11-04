import AppKit

/// "Today: 6,850 keys · 62 wpm" in the menu bar menu, under the status.
/// Filled in as the menu opens rather than watched: the counts change with
/// every key, and a SwiftUI menu that watched them would rebuild while you
/// type (see StatsStore).
@MainActor
final class MenuStatsItem: NSObject {
    static let shared = MenuStatsItem()

    private let item = NSMenuItem()
    private weak var state: AppState?

    func install(state: AppState) {
        self.state = state
        item.isEnabled = false
        MenuOpening.observe { [weak self] menu in self?.opened(menu) }
    }

    private func opened(_ menu: NSMenu) {
        // Only the menu bar menu: it's the one with the volume heading.
        guard let state, menu.items.contains(where: { $0.title == MenuVolumeItem.heading }) else { return }
        item.title = Self.text(today: state.stats.shown.today, wordsPerMinute: state.stats.shown.wordsPerMinute)
        guard item.menu !== menu else { return }
        item.menu?.removeItem(item)
        // The last line of the status block, just above the first divider.
        let at = menu.items.firstIndex(where: \.isSeparatorItem) ?? 1
        menu.insertItem(item, at: at)
    }

    static func text(today: Int, wordsPerMinute: Int?) -> String {
        guard today > 0 else { return "Today: no typing yet" }
        let keys = today == 1 ? "1 key" : "\(today.formatted()) keys"
        return wordsPerMinute.map { "Today: \(keys) · \($0) wpm" } ?? "Today: \(keys)"
    }
}

import Foundation
import UserNotifications

/// Posts a quiet notification when the switch set changes from outside
/// ThockBox's own menus (Shortcuts, AppleScript), so the change isn't a
/// surprise. Off unless the user turns it on.
enum SetChangeNotifier {
    /// Asks once; macOS remembers the answer.
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(setName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Switch set changed"
        content.body = "ThockBox now plays \(setName)."
        // One notification at a time: a newer change replaces the last.
        let request = UNNotificationRequest(identifier: "setChanged", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

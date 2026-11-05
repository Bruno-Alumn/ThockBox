import AppKit

/// Starts a fresh copy of ThockBox, then quits this one.
///
/// The new copy is opened through Launch Services before this one quits.
/// A helper process left to reopen the app after it exits doesn't work:
/// launchd ends everything an app started when the app quits, so the helper
/// dies with it and ThockBox stays closed.
enum Relaunch {
    static func now(_ app: URL = Bundle.main.bundleURL, failed: @escaping (Error) -> Void = { _ in }) {
        // Save the counts first, so the new copy starts from them.
        AppState.shared.flushStats()
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: app, configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error {
                    klog.error("relaunch failed: \(error, privacy: .public)")
                    failed(error)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

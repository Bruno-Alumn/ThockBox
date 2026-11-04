import AppKit
import SwiftUI

/// Names for the apps the media mute sees, and the label for its menu.
enum MediaApps {
    /// The app's name from its bundle ID, or the process name for one
    /// without a bundle.
    static func name(_ bundleID: String) -> String {
        if bundleID.hasPrefix(AudioActivityMonitor.processPrefix) {
            let process = bundleID.dropFirst(AudioActivityMonitor.processPrefix.count)
            return process.isEmpty ? "Other audio" : String(process)
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return MutedAppsList.appName(url)
    }

    /// What the menu's label says: the apps that count now, by name if one.
    static func summary(playing: Set<String>, ignored: Set<String>, name: (String) -> String) -> String {
        let counting = playing.subtracting(ignored)
        switch counting.count {
        case 0: return "None"
        case 1: return name(counting.first!)
        default: return "\(counting.count) apps"
        }
    }
}

/// Which apps' sound counts for the media mute. Lists what's playing now
/// plus any already ignored, so an app can be let back in.
struct MediaAppsChoice: View {
    @ObservedObject var state: AppState

    var body: some View {
        let apps = state.playingApps.union(state.ignoredMediaApps)
            .filter { $0 != AudioActivityMonitor.processPrefix }
            .sorted { MediaApps.name($0).localizedCaseInsensitiveCompare(MediaApps.name($1)) == .orderedAscending }
        LabeledContent("Playing now") {
            Menu(MediaApps.summary(playing: state.playingApps, ignored: state.ignoredMediaApps,
                                   name: MediaApps.name)) {
                if apps.isEmpty {
                    Text("No apps are playing sound")
                }
                ForEach(apps, id: \.self) { id in
                    Toggle(MediaApps.name(id), isOn: Binding(
                        get: { !state.ignoredMediaApps.contains(id) },
                        set: { counts in
                            if counts { state.ignoredMediaApps.remove(id) }
                            else { state.ignoredMediaApps.insert(id) }
                        }))
                }
            }
            .fixedSize()
        }
    }
}

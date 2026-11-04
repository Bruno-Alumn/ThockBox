import AppKit
import SwiftUI

/// Apps that play their own switch set, each with a picker. Everything
/// else plays the set chosen above.
struct AppPacksList: View {
    @ObservedObject var state: AppState
    @State private var selection: Set<String> = []

    private var apps: [String] {
        state.appPacks.keys.sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            List(apps, id: \.self, selection: $selection) { id in
                HStack {
                    let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                    Label {
                        Text(name(id))
                    } icon: {
                        Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .applicationBundle))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Spacer()
                    Picker("Set for \(name(id))", selection: Binding(
                        get: { state.appPacks[id] ?? state.selectedPackID },
                        set: { state.appPacks[id] = $0 })) {
                        ForEach(state.packs) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 110)
            .onDeleteCommand(perform: removeSelection)
            .overlay {
                if state.appPacks.isEmpty {
                    Text("No Apps").foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                Button(action: chooseApps) {
                    Image(systemName: "plus").frame(width: 20, height: 20).contentShape(Rectangle())
                }
                    .help("Add apps")
                    .accessibilityLabel("Add Apps")
                Button(action: removeSelection) {
                    Image(systemName: "minus").frame(width: 20, height: 20).contentShape(Rectangle())
                }
                    .disabled(selection.isEmpty)
                    .help("Remove the selected apps")
                    .accessibilityLabel("Remove Selected Apps")
            }
            .buttonStyle(.borderless)
        }
    }

    private func name(_ id: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map(MutedAppsList.appName) ?? id
    }

    private func removeSelection() {
        selection.forEach { state.appPacks[$0] = nil }
        selection = []
    }

    /// New apps start on the current set; pick a different one in the row.
    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for id in panel.urls.compactMap({ Bundle(url: $0)?.bundleIdentifier }) where state.appPacks[id] == nil {
            state.appPacks[id] = state.selectedPackID
        }
    }
}

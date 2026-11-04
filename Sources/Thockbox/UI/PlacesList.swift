import SwiftUI

/// The saved places, each renamable, with + to add where the Mac is now.
struct PlacesList: View {
    @ObservedObject var state: AppState
    @State private var selection: Set<UUID> = []
    @State private var adding = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            List(selection: $selection) {
                ForEach($state.places) { $place in
                    Label {
                        TextField("Name", text: $place.name)
                            .textFieldStyle(.plain)
                            .accessibilityLabel("Place name")
                    } icon: {
                        Image(systemName: state.placesInside.contains(place.id) ? "location.fill" : "mappin")
                            .foregroundStyle(state.placesInside.contains(place.id) ? Color.accentColor : .secondary)
                            .help(state.placesInside.contains(place.id) ? "You're here now" : "")
                    }
                    .tag(place.id)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 110)
            .onDeleteCommand(perform: removeSelection)
            .overlay {
                if state.places.isEmpty {
                    Text("No Places").foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                Button(action: addHere) {
                    Image(systemName: "plus").frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .disabled(adding || state.places.count >= 20)
                .help("Add where this Mac is now")
                .accessibilityLabel("Add Current Location")
                Button(action: removeSelection) {
                    Image(systemName: "minus").frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .disabled(selection.isEmpty)
                .help("Remove the selected places")
                .accessibilityLabel("Remove Selected Places")
                if adding {
                    ProgressView().controlSize(.small).padding(.leading, 4)
                    Text("Finding this Mac…").foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            if let problem {
                Text(problem).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func addHere() {
        adding = true
        problem = nil
        state.addCurrentPlace { message in
            adding = false
            // A refusal is already explained under the toggle.
            problem = state.locationAccess == .denied ? nil : message
        }
    }

    private func removeSelection() {
        state.places.removeAll { selection.contains($0.id) }
        selection = []
    }
}

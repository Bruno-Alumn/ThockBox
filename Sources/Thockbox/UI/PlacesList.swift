import SwiftUI

/// The saved places as rows of the settings form, each renamable and
/// removable, then a button to add where the Mac is now.
///
/// Plain rows rather than a List: a scrolling List nested in the Form, shown
/// only once "Use your location" is on, laid out wrong (its rows drew over
/// the row above and its + and − buttons were cut off).
struct PlacesList: View {
    @ObservedObject var state: AppState
    @State private var adding = false
    @State private var problem: String?

    var body: some View {
        ForEach($state.places) { $place in
            let here = state.placesInside.contains(place.id)
            HStack(spacing: 8) {
                Image(systemName: here ? "location.fill" : "mappin")
                    .foregroundStyle(here ? Color.accentColor : .secondary)
                    .frame(width: 16)
                    .help(here ? "You're here now" : "")
                    .accessibilityLabel(here ? "You're here now" : "")
                    .accessibilityHidden(!here)
                TextField("Name", text: $place.name)
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .accessibilityLabel("Place name")
                Button {
                    state.places.removeAll { $0.id == place.id }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove \(place.name)")
                .accessibilityLabel("Remove \(place.name)")
            }
        }
        HStack(spacing: 8) {
            Button("Add Current Location", action: addHere)
                .disabled(adding || state.places.count >= 20)
                .help(state.places.count >= 20 ? "macOS watches at most 20 places" : "Save where this Mac is now")
            if adding {
                ProgressView().controlSize(.small)
                Text("Finding your location…").foregroundStyle(.secondary)
            }
            Spacer()
        }
        if let problem {
            Text(problem).font(.footnote).foregroundStyle(.secondary)
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
}

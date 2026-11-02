import AppIntents

/// Actions for the Shortcuts app, Siri and Spotlight, so ThockBox can follow
/// a Focus or any other automation. They run inside the menu bar app.
/// (`make bundle` generates the metadata Shortcuts reads; see
/// scripts/build_intents_metadata.sh.)

struct SetSoundsIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn ThockBox Sounds On or Off"
    static var description = IntentDescription("Turns keyboard sounds on or off.")

    @Parameter(title: "Sounds", default: true, displayName: Bool.IntentDisplayName(true: "On", false: "Off"))
    var on: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Turn ThockBox sounds \(\.$on)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.enabled = on
        return .result()
    }
}

struct ToggleSoundsIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle ThockBox Sounds"
    static var description = IntentDescription("Turns keyboard sounds on if they're off, and off if they're on.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        AppState.shared.enabled.toggle()
        return .result(value: AppState.shared.enabled)
    }
}

struct SetSwitchSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Set ThockBox Switch Set"
    static var description = IntentDescription("Chooses which switch set ThockBox plays.")

    @Parameter(title: "Switch Set")
    var switchSet: SwitchSetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Set the switch set to \(\.$switchSet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.selectedPackID = switchSet.id
        return .result()
    }
}

struct SetVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set ThockBox Volume"
    static var description = IntentDescription("Sets the volume of keyboard sounds, from 0 to 100 percent.")

    @Parameter(title: "Volume", inclusiveRange: (0, 100))
    var percent: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set ThockBox volume to \(\.$percent)%")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.volume = Float(min(max(percent, 0), 100)) / 100
        return .result()
    }
}

/// A switch set, as Shortcuts lists and picks it.
struct SwitchSetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Switch Set"
    static var defaultQuery = SwitchSetQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SwitchSetQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [SwitchSetEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SwitchSetEntity] {
        all()
    }

    @MainActor
    private func all() -> [SwitchSetEntity] {
        AppState.shared.packs.map { SwitchSetEntity(id: $0.id, name: $0.name) }
    }
}

/// Ready-made shortcuts: they show up in Spotlight and Siri with no setup.
struct ThockBoxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ToggleSoundsIntent(),
                    phrases: ["Toggle \(.applicationName) sounds", "Toggle \(.applicationName)"],
                    shortTitle: "Toggle Sounds", systemImageName: "keyboard")
        AppShortcut(intent: SetSwitchSetIntent(),
                    phrases: ["Set the \(.applicationName) switch set", "Change \(.applicationName) switches"],
                    shortTitle: "Set Switch Set", systemImageName: "slider.horizontal.3")
    }
}

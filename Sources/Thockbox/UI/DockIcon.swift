import AppKit
import Combine
import CoreImage

/// How ThockBox's icon looks in the Dock (shown while a ThockBox window is
/// open) and in its own windows. The icon file in Applications doesn't
/// change: rewriting the app bundle would break its signature and with it
/// the Accessibility grant.
enum DockIconStyle: String, CaseIterable, Identifiable {
    case color
    case graphite
    /// Color while keys make sound, graphite while they don't.
    case followsSounds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .color: "Color"
        case .graphite: "Graphite"
        case .followsSounds: "Graphite while sounds are off"
        }
    }

    func isGraphite(soundsPlaying: Bool) -> Bool {
        switch self {
        case .color: false
        case .graphite: true
        case .followsSounds: !soundsPlaying
        }
    }
}

@MainActor
enum DockIcon {
    private static let color: NSImage? = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap(NSImage.init(contentsOf:))
    private static let graphite: NSImage? = color.flatMap(desaturated)
    private static var shownGraphite: Bool?
    private static var observer: AnyCancellable?

    /// Keeps the icon in step with the style and, for followsSounds, with
    /// whether sounds are playing.
    static func install(state: AppState) {
        apply(state)
        // objectWillChange fires before the change lands; read it a beat later.
        observer = state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak state] _ in
                if let state { apply(state) }
            }
    }

    private static func apply(_ state: AppState) {
        let graphiteNow = state.dockIconStyle.isGraphite(soundsPlaying: state.status.isPlaying)
        guard graphiteNow != shownGraphite, let color else { return }
        shownGraphite = graphiteNow
        NSApp.applicationIconImage = graphiteNow ? (graphite ?? color) : color
    }

    /// The icon in grays, a little lighter so it reads as "resting".
    static func desaturated(_ image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation, let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        filter.setValue(0.05, forKey: kCIInputBrightnessKey)
        guard let output = filter.outputImage else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let result = NSImage(size: image.size)
        result.addRepresentation(rep)
        return result
    }
}

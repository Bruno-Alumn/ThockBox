import AppKit
import XCTest
@testable import Thockbox

final class DockIconTests: XCTestCase {
    func testStyles() {
        XCTAssertFalse(DockIconStyle.color.isGraphite(soundsPlaying: false))
        XCTAssertTrue(DockIconStyle.graphite.isGraphite(soundsPlaying: true))
        XCTAssertFalse(DockIconStyle.followsSounds.isGraphite(soundsPlaying: true))
        XCTAssertTrue(DockIconStyle.followsSounds.isGraphite(soundsPlaying: false))
    }

    @MainActor
    func testGraphiteHasNoColor() throws {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor(srgbRed: 1, green: 0.475, blue: 0.322, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let gray = try XCTUnwrap(DockIcon.desaturated(image))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(gray.tiffRepresentation)))
        let c = try XCTUnwrap(rep.colorAt(x: 4, y: 4)?.usingColorSpace(.sRGB))
        XCTAssertEqual(c.redComponent, c.greenComponent, accuracy: 0.02)
        XCTAssertEqual(c.greenComponent, c.blueComponent, accuracy: 0.02)
    }

    func testTheChoiceSurvivesARelaunch() {
        let suite = "ThockboxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppState(defaults: defaults).dockIconStyle, .color)
        AppState(defaults: defaults).dockIconStyle = .followsSounds
        XCTAssertEqual(AppState(defaults: defaults).dockIconStyle, .followsSounds)
    }
}

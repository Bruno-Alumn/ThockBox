import CoreLocation
import XCTest
@testable import Thockbox

@MainActor
final class PlacesTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "ThockboxTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private let office = Place(name: "Office", latitude: 51.5, longitude: -0.12)
    private let library = Place(name: "Library", latitude: 51.6, longitude: -0.1)

    private func makeState() -> AppState {
        let state = AppState(defaults: defaults)
        state.watchesPlaces = false
        state.places = [office, library]
        return state
    }

    func testMutesAtAPlaceOnlyWhenTurnedOn() {
        let state = makeState()
        state.setPlaces(inside: [office.id], known: true)
        XCTAssertNil(state.automaticMute, "muting by place is off")
        state.muteByPlace = true
        state.setPlaces(inside: [office.id], known: true)
        XCTAssertEqual(state.automaticMute, .place("Office"))
        state.setPlaces(inside: [], known: true)
        XCTAssertNil(state.automaticMute)
    }

    func testPlayOnlyAtPlacesMutesEverywhereElse() {
        let state = makeState()
        state.muteByPlace = true
        state.playOnlyAtPlaces = true
        state.setPlaces(inside: [], known: true)
        XCTAssertEqual(state.automaticMute, .place(nil))
        state.setPlaces(inside: [library.id], known: true)
        XCTAssertNil(state.automaticMute)
    }

    func testNothingMutesUntilMacOSHasReported() {
        let state = makeState()
        state.muteByPlace = true
        state.playOnlyAtPlaces = true
        state.setPlaces(inside: [], known: false)
        XCTAssertNil(state.automaticMute, "no answer yet, or no Location access")
    }

    func testMutesAtAPlaceBeforeEveryPlaceHasAnAnswer() {
        let state = makeState()
        state.muteByPlace = true
        state.setPlaces(inside: [office.id], known: false)
        XCTAssertEqual(state.automaticMute, .place("Office"), "the library still has no answer")
    }

    func testRenamingAPlaceKeepsPlayAnyway() {
        let state = makeState()
        state.muteByPlace = true
        state.setPlaces(inside: [office.id], known: true)
        state.playAnyway()
        state.places[0].name = "Work"
        XCTAssertNil(state.automaticMute)
    }

    func testNoPlacesNeverMutes() {
        let state = AppState(defaults: defaults)
        state.watchesPlaces = false
        state.muteByPlace = true
        state.playOnlyAtPlaces = true
        state.setPlaces(inside: [], known: true)
        XCTAssertNil(state.automaticMute)
    }

    func testTurningOffForgetsWhereTheMacIs() {
        let state = makeState()
        state.muteByPlace = true
        state.setPlaces(inside: [office.id], known: true)
        state.muteByPlace = false
        XCTAssertNil(state.automaticMute)
        XCTAssertTrue(state.placesInside.isEmpty)
    }

    func testPlayAnywayPlaysThroughAPlace() {
        let state = makeState()
        state.muteByPlace = true
        state.setPlaces(inside: [office.id], known: true)
        state.playAnyway()
        XCTAssertNil(state.automaticMute)
        // Leaving and coming back mutes again.
        state.setPlaces(inside: [], known: true)
        state.setPlaces(inside: [office.id], known: true)
        XCTAssertEqual(state.automaticMute, .place("Office"))
    }

    func testOtherReasonsStillCountAtAPlace() {
        let state = makeState()
        state.readsCalendars = false
        state.muteByPlace = true
        state.muteDuringMeetings = true
        state.setPlaces(inside: [office.id], known: true)
        state.setInCalendarEvent(true)
        XCTAssertEqual(state.automaticMute, .meeting, "a meeting comes first")
        state.setInCalendarEvent(false)
        XCTAssertEqual(state.automaticMute, .place("Office"))
    }

    func testPlacesAreSavedAndRenamesKeepTheirID() {
        let state = makeState()
        state.places[0].name = "Work"
        let reloaded = AppState(defaults: defaults)
        XCTAssertEqual(reloaded.places.map(\.name), ["Work", "Library"])
        XCTAssertEqual(reloaded.places[0].id, office.id)
    }

    func testRegionMatchesThePlace() {
        let region = PlaceMonitor.region(for: office)
        XCTAssertEqual(region.identifier, office.id.uuidString)
        XCTAssertEqual(region.radius, 200)
        XCTAssertTrue(region.notifyOnEntry && region.notifyOnExit)
    }

    private func fix(metersNorth: Double, accuracy: Double) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: office.latitude + metersNorth / 111_000,
                                                      longitude: office.longitude),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: Date())
    }

    func testASharpFixSettlesAPlace() {
        XCTAssertEqual(PlaceMonitor.contains(office, fix(metersNorth: 110, accuracy: 40)), true)
        XCTAssertEqual(PlaceMonitor.contains(office, fix(metersNorth: 1000, accuracy: 40)), false)
        // Near the edge a sharp fix still decides.
        XCTAssertEqual(PlaceMonitor.contains(office, fix(metersNorth: 180, accuracy: 40)), true)
        XCTAssertEqual(PlaceMonitor.contains(office, fix(metersNorth: 220, accuracy: 40)), false)
    }

    /// A fix "within 300 m" that lands 250 m away doesn't show the Mac left.
    func testAVagueFixNearAPlaceDecidesNothing() {
        XCTAssertNil(PlaceMonitor.contains(office, fix(metersNorth: 250, accuracy: 300)))
        XCTAssertNil(PlaceMonitor.contains(office, fix(metersNorth: 100, accuracy: 300)))
        // Far enough away, even a vague fix is sure.
        XCTAssertEqual(PlaceMonitor.contains(office, fix(metersNorth: 2000, accuracy: 300)), false)
    }

    func testVagueOrOldFixesAreIgnored() {
        let here = CLLocationCoordinate2D(latitude: 40, longitude: -3)
        func fix(accuracy: Double, age: TimeInterval) -> CLLocation {
            CLLocation(coordinate: here, altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1,
                       timestamp: Date(timeIntervalSinceNow: -age))
        }
        XCTAssertTrue(PlaceMonitor.isUsable(fix(accuracy: 65, age: 5)))
        XCTAssertFalse(PlaceMonitor.isUsable(fix(accuracy: 3000, age: 5)))
        XCTAssertFalse(PlaceMonitor.isUsable(fix(accuracy: -1, age: 5)))
        XCTAssertFalse(PlaceMonitor.isUsable(fix(accuracy: 65, age: 600)))
    }

    /// Play Anyway through one app's music holds when another app chimes in.
    func testMediaStaysTheSameReasonWhicheverAppsPlay() {
        XCTAssertTrue(AutomaticMute.media("Spotify").isSame(as: .media(nil)))
        XCTAssertFalse(AutomaticMute.media("Spotify").isSame(as: .call))
    }

    func testStatusNamesThePlace() {
        XCTAssertEqual(PlaybackStatus.muted(.place("Office")).title, "Muted at Office")
        XCTAssertEqual(PlaybackStatus.muted(.place(nil)).title, "Muted away from your places")
    }

    func testPlacesStayOutOfExportedSettings() throws {
        let state = makeState()
        state.muteByPlace = true
        let data = try SettingsTransfer.export(from: defaults)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("muteByPlace"))
        XCTAssertFalse(text.contains("Library"), "coordinates and names aren't exported")
    }
}

import CoreAudio
import XCTest
@testable import Thockbox

final class HeadphonesOnlyTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "ThockboxTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testWhatCountsAsSpeakers() {
        let internalSpeaker: UInt32 = 0x6973_706B // 'ispk'
        XCTAssertTrue(AudioDevices.isSpeaker(transport: kAudioDeviceTransportTypeBuiltIn, dataSource: internalSpeaker))
        XCTAssertTrue(AudioDevices.isSpeaker(transport: kAudioDeviceTransportTypeBuiltIn, dataSource: nil), "unsure counts as speakers")
        XCTAssertFalse(AudioDevices.isSpeaker(transport: kAudioDeviceTransportTypeBuiltIn,
                                              dataSource: AudioDevices.headphoneDataSource), "headphone jack")
        XCTAssertTrue(AudioDevices.isSpeaker(transport: kAudioDeviceTransportTypeHDMI, dataSource: nil))
        XCTAssertTrue(AudioDevices.isSpeaker(transport: kAudioDeviceTransportTypeDisplayPort, dataSource: nil))
        XCTAssertTrue(AudioDevices.isSpeaker(transport: kAudioDeviceTransportTypeAirPlay, dataSource: nil))
        XCTAssertFalse(AudioDevices.isSpeaker(transport: kAudioDeviceTransportTypeBluetooth, dataSource: nil))
        XCTAssertFalse(AudioDevices.isSpeaker(transport: kAudioDeviceTransportTypeUSB, dataSource: nil))
    }

    func testMutesOnSpeakersOnlyWhenOn() {
        let state = AppState(defaults: defaults)
        state.setOutputIsSpeaker(true)
        XCTAssertNil(state.automaticMute, "off by default")

        state.headphonesOnly = true
        XCTAssertEqual(state.automaticMute, .speakers)
        XCTAssertEqual(state.status.title, "Muted on speakers")
        state.setOutputIsSpeaker(false)
        XCTAssertNil(state.automaticMute, "headphones connected")
        XCTAssertTrue(AppState(defaults: defaults).headphonesOnly, "saved")
    }

    /// A picked device that's unplugged and plugged back in gets the sound
    /// back, instead of staying on the speakers until it's picked again.
    func testPickedDeviceIsReappliedWhenItComesAndGoes() {
        // 42: the picked USB device, 7: speakers (default), 9: a new default.
        XCTAssertFalse(AppState.needsReapply(target: 42, applied: 42), "already there")
        XCTAssertTrue(AppState.needsReapply(target: 7, applied: 42), "unplugged: go to the default now")
        XCTAssertFalse(AppState.needsReapply(target: 7, applied: 7), "still unplugged, same default")
        XCTAssertTrue(AppState.needsReapply(target: 9, applied: 7), "default changed while unplugged")
        XCTAssertTrue(AppState.needsReapply(target: 57, applied: 7), "plugged back in with a new id")
    }

    /// With System Default chosen after a specific device, the engine is
    /// pinned to the default of that moment; a new default must be followed.
    func testSystemDefaultFollowsTheDefault() {
        XCTAssertTrue(AppState.needsReapply(target: 7, applied: nil), "first time: point it")
        XCTAssertFalse(AppState.needsReapply(target: 7, applied: 7))
        XCTAssertTrue(AppState.needsReapply(target: 9, applied: 7), "headphones became the default")
    }

    /// A picked device keeps its last known name while it's unplugged, so
    /// Settings can show "AirPods Pro (Not Connected)" instead of a blank.
    func testUnpluggedDeviceKeepsItsName() throws {
        let suite = "ThockboxTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("AirPods Pro", forKey: "outputDeviceName")
        let state = AppState(defaults: defaults)
        state.outputDeviceUID = "not-connected-uid"
        XCTAssertEqual(state.outputDeviceName, "AirPods Pro")
    }

    func testSpatialAudioOnlyOnHeadphones() {
        XCTAssertTrue(AppState.usesSpatial(setting: true, outputIsSpeaker: false))
        XCTAssertFalse(AppState.usesSpatial(setting: true, outputIsSpeaker: true), "speakers stay 2D")
        XCTAssertFalse(AppState.usesSpatial(setting: false, outputIsSpeaker: false))
    }
}

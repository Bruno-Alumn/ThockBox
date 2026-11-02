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
}

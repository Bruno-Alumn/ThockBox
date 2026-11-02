import XCTest
@testable import Thockbox

final class PlaybackStatusTests: XCTestCase {
    private func status(trusted: Bool = true, enabled: Bool = true, secure: String? = nil,
                        mute: AutomaticMute? = nil) -> PlaybackStatus {
        .from(trusted: trusted, enabled: enabled, shortcut: "⌃⌘K", secureInputApp: secure, mute: mute, pack: "Cream")
    }

    /// The first thing that stops sound is the one shown.
    func testPriority() {
        XCTAssertEqual(status(), .playing(pack: "Cream"))
        XCTAssertEqual(status(mute: .idle), .muted(.idle))
        XCTAssertEqual(status(secure: "Terminal", mute: .idle), .blocked(app: "Terminal"))
        XCTAssertEqual(status(enabled: false, secure: "Terminal"), .off(shortcut: "⌃⌘K"))
        XCTAssertEqual(status(trusted: false, enabled: false), .needsAccess)
    }

    func testOnlyProblemsAskForAttention() {
        XCTAssertTrue(status(trusted: false).needsAttention)
        XCTAssertTrue(status(secure: "Terminal").needsAttention)
        XCTAssertFalse(status(enabled: false).needsAttention, "turning sounds off is a choice")
        XCTAssertFalse(status(mute: .call).needsAttention)
    }

    func testWording() {
        XCTAssertEqual(status(mute: .app("Safari")).title, "Muted in Safari")
        XCTAssertEqual(status(enabled: false).detail, "Turn it on here or with ⌃⌘K.")
        XCTAssertNil(status().detail)
    }
}

import XCTest
@testable import Thockbox

final class WhatsNewTests: XCTestCase {
    private let changelog = """
    # Changelog

    ## Unreleased

    - Something not shipped yet.

    ## 1.2.0

    - **Mute while playing a game** (Settings › Muting): any app filed under
      Games.
    - AppleScript: `mute while gaming`.

    ## 1.1.2

    - Older.
    """

    func testReadsTheVersionsSectionAndJoinsWrappedBullets() {
        let notes = WhatsNew.parse(changelog: changelog, version: "1.2.0")
        XCTAssertEqual(notes, WhatsNew(version: "1.2.0", items: [
            "**Mute while playing a game** (Settings › Muting): any app filed under Games.",
            "AppleScript: `mute while gaming`.",
        ]))
    }

    func testWithoutAVersionItsTheNewestReleaseNotUnreleased() {
        XCTAssertEqual(WhatsNew.parse(changelog: changelog)?.version, "1.2.0")
    }

    func testAVersionWithoutNotesHasNone() {
        XCTAssertNil(WhatsNew.parse(changelog: changelog, version: "9.9"))
    }

    func testOnlyShownAfterAnUpdate() {
        XCTAssertTrue(WhatsNew.isUpdate(lastVersion: "1.1.2", current: "1.2.0", usedBefore: true))
        XCTAssertFalse(WhatsNew.isUpdate(lastVersion: "1.2.0", current: "1.2.0", usedBefore: true))
        XCTAssertFalse(WhatsNew.isUpdate(lastVersion: nil, current: "1.2.0", usedBefore: false), "a new install")
        XCTAssertTrue(WhatsNew.isUpdate(lastVersion: nil, current: "1.2.0", usedBefore: true),
                      "an update from a version that didn't record itself")
    }

    /// The real CHANGELOG parses, so the window has something to show.
    func testTheRealChangelogHasNotes() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CHANGELOG.md")
        let notes = try XCTUnwrap(WhatsNew.parse(changelog: String(contentsOf: url, encoding: .utf8)))
        XCTAssertFalse(notes.items.isEmpty)
    }
}

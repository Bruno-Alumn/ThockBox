import XCTest
@testable import Thockbox

final class ReleaseNotesTests: XCTestCase {
    private func release(body: String) throws -> Release {
        let object: [String: Any] = ["tag_name": "v1.1.0", "html_url": "https://example.com",
                                     "body": body, "assets": [Any]()]
        return try JSONDecoder().decode(Release.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// The shape of GitHub's generated notes (`gh release create --generate-notes`).
    func testPreviewKeepsJustTheChanges() throws {
        let body = "## What's Changed\r\n"
            + "* Mute during calls by @Bruno-Alumn in https://github.com/Bruno-Alumn/ThockBox/pull/1\r\n"
            + "* Use no CPU when idle by @Bruno-Alumn in https://github.com/Bruno-Alumn/ThockBox/pull/16\r\n\r\n\r\n"
            + "**Full Changelog**: https://github.com/Bruno-Alumn/ThockBox/compare/v1.0.0...v1.1.0"
        XCTAssertEqual(try release(body: body).notesPreview, "• Mute during calls\n• Use no CPU when idle")
    }

    func testNotesWithNothingButAHeadingHaveNoPreview() throws {
        XCTAssertNil(try release(body: "## What's Changed\n").notesPreview)
    }
}

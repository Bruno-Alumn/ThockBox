import XCTest
@testable import Thockbox

final class UpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(AppVersion.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(AppVersion.isNewer("1.10.0", than: "1.9.0"))
        XCTAssertTrue(AppVersion.isNewer("2", than: "1.9.9"))
        XCTAssertFalse(AppVersion.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(AppVersion.isNewer("1.0.0", than: "1.0.1"))
        XCTAssertFalse(AppVersion.isNewer("1.1.0-beta", than: "1.1.0"))
    }

    func testDecodesGitHubRelease() throws {
        let json = """
        {
          "tag_name": "v1.2.0",
          "html_url": "https://github.com/Bruno-Alumn/ThockBox/releases/tag/v1.2.0",
          "body": "Notes",
          "assets": [
            {"name": "checksums.txt", "browser_download_url": "https://example.com/checksums.txt"},
            {"name": "ThockBox-1.2.0.zip", "browser_download_url": "https://example.com/ThockBox-1.2.0.zip"}
          ]
        }
        """
        let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))
        XCTAssertEqual(release.version, "1.2.0")
        XCTAssertEqual(release.appArchive?.name, "ThockBox-1.2.0.zip")
    }

    func testReleaseWithoutZipHasNoArchive() throws {
        let json = """
        {"tag_name": "1.2.0", "html_url": "https://example.com", "body": null, "assets": []}
        """
        let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))
        XCTAssertEqual(release.version, "1.2.0")
        XCTAssertNil(release.appArchive)
    }
}

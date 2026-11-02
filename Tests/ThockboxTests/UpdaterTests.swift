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

    func testPrefersTheDiskImageAndFallsBackToAZip() throws {
        func release(_ names: [String]) throws -> Release {
            let assets = names.map { ["name": $0, "browser_download_url": "https://example.com/\($0)"] }
            let object: [String: Any] = ["tag_name": "v1.2.0", "html_url": "https://example.com", "assets": assets]
            return try JSONDecoder().decode(Release.self, from: JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertEqual(try release(["ThockBox-1.2.0.zip", "ThockBox-1.2.0.dmg"]).appArchive?.name, "ThockBox-1.2.0.dmg")
        XCTAssertEqual(try release(["ThockBox-1.1.0.zip"]).appArchive?.name, "ThockBox-1.1.0.zip", "older releases")
        XCTAssertNil(try release(["Other.dmg"]).appArchive)
    }

    func testReleaseWithoutZipHasNoArchive() throws {
        let json = """
        {"tag_name": "1.2.0", "html_url": "https://example.com", "body": null, "assets": []}
        """
        let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))
        XCTAssertEqual(release.version, "1.2.0")
        XCTAssertNil(release.appArchive)
    }

    /// A manual check says what went wrong, not always "couldn't reach GitHub".
    @MainActor
    func testCheckFailureMessages() {
        XCTAssertEqual(Updater.checkFailure(URLError(.notConnectedToInternet)), "Your Mac isn't connected to the internet.")
        XCTAssertEqual(Updater.checkFailure(URLError(.cannotFindHost)), "Couldn't reach GitHub. Try again later.")
        XCTAssertTrue(Updater.checkFailure(URLError(.timedOut)).hasPrefix("GitHub took too long"))
        XCTAssertTrue(Updater.checkFailure(HTTPStatusError(code: 403)).contains("limiting update checks"))
        XCTAssertTrue(Updater.checkFailure(HTTPStatusError(code: 429)).contains("limiting update checks"))
        XCTAssertTrue(Updater.checkFailure(HTTPStatusError(code: 502)).hasPrefix("GitHub isn't working"))
        XCTAssertTrue(Updater.checkFailure(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))).contains("couldn't be read"))
    }
}

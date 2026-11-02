import XCTest
@testable import Thockbox

final class MutedAppsListTests: XCTestCase {
    /// The app's name, not its file name, whatever Finder shows.
    func testAppNameComesFromTheBundle() throws {
        let safari = URL(fileURLWithPath: "/Applications/Safari.app")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: safari.path))
        XCTAssertEqual(MutedAppsList.appName(safari), "Safari")
        let missing = URL(fileURLWithPath: "/nonexistent/Some Tool.app")
        XCTAssertEqual(MutedAppsList.appName(missing), "Some Tool")
    }
}

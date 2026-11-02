import XCTest
@testable import Thockbox

final class ProblemReportTests: XCTestCase {
    func testOpensANewIssueWithOnlyTheVersions() throws {
        let url = ProblemReport.url(appVersion: "1.1.1", osVersion: "Version 26.1 (Build 25B78)")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/Bruno-Alumn/ThockBox/issues/new")
        XCTAssertEqual(components.queryItems?.map(\.name), ["body"])
        let body = try XCTUnwrap(components.queryItems?.first?.value)
        XCTAssertTrue(body.hasSuffix("ThockBox 1.1.1, macOS Version 26.1 (Build 25B78)"))
    }
}

import XCTest
@testable import Thockbox

/// Answers every request with a canned GitHub reply.
private final class StubGitHub: URLProtocol {
    static var reply: Result<(status: Int, body: String), URLError> = .success((404, ""))
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lastRequest = request
        switch Self.reply {
        case .success(let reply):
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

@MainActor
final class UpdateCheckTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "ThockboxTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func updater(version: String = "1.0.0") -> Updater {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubGitHub.self]
        return Updater(defaults: defaults, session: URLSession(configuration: config), currentVersion: version)
    }

    private func release(_ tag: String) -> String {
        """
        {"tag_name": "\(tag)", "html_url": "https://github.com/Bruno-Alumn/ThockBox/releases/tag/\(tag)",
         "body": "", "assets": [{"name": "ThockBox-1.1.0.zip", "browser_download_url": "https://example.com/a.zip"}]}
        """
    }

    func testNewerReleaseIsOffered() async {
        StubGitHub.reply = .success((200, release("v1.1.0")))
        let updater = updater()
        await updater.check(userInitiated: false)
        XCTAssertEqual(updater.availableRelease?.version, "1.1.0")
        XCTAssertNotNil(defaults.object(forKey: "lastUpdateCheck"), "a successful check is remembered")
        XCTAssertEqual(StubGitHub.lastRequest?.url?.path, "/repos/Bruno-Alumn/ThockBox/releases/latest")
        XCTAssertEqual(StubGitHub.lastRequest?.value(forHTTPHeaderField: "User-Agent"), "ThockBox/1.0.0")
    }

    func testSameOrOlderReleaseIsUpToDate() async {
        StubGitHub.reply = .success((200, release("v1.0.0")))
        let updater = updater()
        await updater.check(userInitiated: true)
        XCTAssertEqual(updater.status, .upToDate)
    }

    func testNoReleasesYetIsUpToDate() async {
        StubGitHub.reply = .success((404, #"{"message": "Not Found"}"#))
        let updater = updater()
        await updater.check(userInitiated: true)
        XCTAssertEqual(updater.status, .upToDate)
    }

    func testNetworkErrorsShowOnlyForManualChecks() async {
        StubGitHub.reply = .failure(URLError(.notConnectedToInternet))
        let updater = updater()
        await updater.check(userInitiated: false)
        XCTAssertEqual(updater.status, .idle, "a background failure stays quiet")
        XCTAssertNil(defaults.object(forKey: "lastUpdateCheck"), "and is retried later")
        await updater.check(userInitiated: true)
        guard case .failed = updater.status else { return XCTFail("got \(updater.status)") }
    }

    func testServerErrorIsAFailure() async {
        StubGitHub.reply = .success((500, ""))
        let updater = updater()
        await updater.check(userInitiated: true)
        guard case .failed = updater.status else { return XCTFail("got \(updater.status)") }
    }
}

import XCTest
@testable import Thockbox

final class SecureInputTests: XCTestCase {
    func testNamesTheAppHoldingSecureInput() {
        XCTAssertEqual(SecureInput.holderName(bundleID: "com.apple.Terminal", name: "Terminal"), "Terminal")
        XCTAssertEqual(SecureInput.holderName(bundleID: nil, name: nil), "Another app")
    }

    func testTheLockScreenIsNotReported() {
        XCTAssertNil(SecureInput.holderName(bundleID: "com.apple.loginwindow", name: "loginwindow"))
    }
}

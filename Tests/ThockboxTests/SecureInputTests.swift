import XCTest
@testable import Thockbox

final class SecureInputTests: XCTestCase {
    func testNamesTheAppHoldingSecureInput() {
        XCTAssertEqual(AppState.secureInputHolderName(bundleID: "com.apple.Terminal", name: "Terminal"), "Terminal")
        XCTAssertEqual(AppState.secureInputHolderName(bundleID: nil, name: nil), "Another app")
    }

    func testTheLockScreenIsNotReported() {
        XCTAssertNil(AppState.secureInputHolderName(bundleID: "com.apple.loginwindow", name: "loginwindow"))
    }
}

import XCTest
@testable import Thockbox

final class VoiceIndexTests: XCTestCase {
    private func pick(next: Int, busy: Set<Int>, count: Int = 8) -> Int {
        SoundEngine.voiceIndex(next: next, count: count) { busy.contains($0) }
    }

    func testTakesTheNextVoiceWhenItIsFree() {
        XCTAssertEqual(pick(next: 3, busy: []), 3)
    }

    func testSkipsBusyVoices() {
        XCTAssertEqual(pick(next: 3, busy: [3, 4]), 5)
    }

    func testWrapsAround() {
        XCTAssertEqual(pick(next: 6, busy: [6, 7]), 0)
    }

    func testCutsTheNextVoiceOnlyWhenAllAreBusy() {
        XCTAssertEqual(pick(next: 2, busy: Set(0..<8)), 2)
    }
}

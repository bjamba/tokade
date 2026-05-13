@testable import Tokade
import XCTest

/// Smoke test — proves the test target builds and runs.
final class SmokeTests: XCTestCase {
    func testFormatCount() {
        XCTAssertEqual(formatCount(0), "0")
        XCTAssertEqual(formatCount(999), "999")
        XCTAssertEqual(formatCount(1000), "1.0k")
        XCTAssertEqual(formatCount(1500), "1.5k")
        XCTAssertEqual(formatCount(999_999), "1000.0k")
        XCTAssertEqual(formatCount(1_000_000), "1.0M")
        XCTAssertEqual(formatCount(2_500_000), "2.5M")
    }
}

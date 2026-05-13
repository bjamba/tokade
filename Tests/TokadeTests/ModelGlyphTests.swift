@testable import Tokade
import XCTest

/// Shape glyph per tier gives colorblind users a second visual channel so
/// the blue-family palette isn't the only differentiator. Lock the
/// mapping so future changes are conscious.
final class ModelGlyphTests: XCTestCase {
    func testHaikuIsCircle() {
        XCTAssertEqual(modelGlyph("claude-haiku-4-5"), "●")
    }

    func testSonnetIsSquare() {
        XCTAssertEqual(modelGlyph("claude-sonnet-4-6"), "■")
    }

    func testOpusIsTriangle() {
        XCTAssertEqual(modelGlyph("claude-opus-4-7"), "▲")
    }

    func testUnknownIsDiamond() {
        XCTAssertEqual(modelGlyph("some-future-model"), "◆")
    }
}

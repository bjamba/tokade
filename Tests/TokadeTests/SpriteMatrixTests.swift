@testable import Tokade
import XCTest

final class SpriteMatrixTests: XCTestCase {
    func testParseSkipsCommentsAndBlankLines() throws {
        let txt = """
        # header comment
        # palette: stuff

        .12.
        2222
        .11.
        """
        let m = try SpriteMatrix.parse(txt)
        XCTAssertEqual(m.width, 4)
        XCTAssertEqual(m.height, 3)
        XCTAssertEqual(m.rows[1], Array("2222"))
    }

    func testRaggedRowsThrow() {
        let txt = """
        ....
        ...
        """
        XCTAssertThrowsError(try SpriteMatrix.parse(txt))
    }

    func testEmptyThrows() {
        XCTAssertThrowsError(try SpriteMatrix.parse("# only comments"))
    }

    func testParsesFullDesignFolderMatrix() throws {
        // Read straight off the filesystem — the app-bundle resource path
        // isn't accessible from the xctest harness, so we go through the
        // workspace path. Keeps the test honest about matrix-format
        // compatibility with the actual baked artifacts.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("design/tokegotchi/animation/walk-idle.matrix")
        let txt = try String(contentsOf: url, encoding: .utf8)
        let m = try SpriteMatrix.parse(txt)
        XCTAssertEqual(m.width, 32)
        XCTAssertTrue((48...60).contains(m.height), "height out of range: \(m.height)")
    }
}

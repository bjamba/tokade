@testable import Tokade
import XCTest

final class SpriteComposerTests: XCTestCase {
    private func parse(_ text: String) -> SpriteMatrix {
        try! SpriteMatrix.parse(text)
    }

    func testEmptyLayersReturnsBaseUnchanged() {
        let base = parse(".22.\n.22.\n....")
        let result = SpriteComposer.compose(base: base, layers: [])
        XCTAssertEqual(result.rows, base.rows)
    }

    func testTopLayerWinsForNonTransparentCells() {
        let base = parse("2222\n2222\n2222")
        let hat = parse(".55.\n....\n....")
        let result = SpriteComposer.compose(base: base, layers: [hat])
        // Transparent cells in the layer let the base show through.
        XCTAssertEqual(result.rows[0], Array("2552"))
        XCTAssertEqual(result.rows[1], Array("2222"))
    }

    func testTransparentInLayerPreservesBase() {
        let base = parse("2222\n2222\n2222")
        let layer = parse(".5..\n....\n..5.")
        let r = SpriteComposer.compose(base: base, layers: [layer])
        XCTAssertEqual(r.rows[0], Array("2522"))
        XCTAssertEqual(r.rows[1], Array("2222"))
        XCTAssertEqual(r.rows[2], Array("2252"))
    }

    func testThreeLayerOrder() {
        let base  = parse("....\n....")
        let l1    = parse("11..\n....")
        let l2    = parse(".22.\n....")
        let l3    = parse("..33\n....")
        let r     = SpriteComposer.compose(base: base, layers: [l1, l2, l3])
        // Each later layer paints over earlier. Final row should be 1233 (l1 only
        // contributes col 0; l2 paints col 1+2; l3 paints col 2+3).
        XCTAssertEqual(r.rows[0], Array("1233"))
    }

    func testMismatchedDimensionsAreSkipped() {
        let base  = parse("22\n22")
        let wrong = parse("....")    // 4 wide, 1 tall — doesn't match
        let ok    = parse("55\n..")
        let r     = SpriteComposer.compose(base: base, layers: [wrong, ok])
        XCTAssertEqual(r.rows[0], Array("55"))
        XCTAssertEqual(r.rows[1], Array("22"))
    }

    func testOrderedLayersWithNilsSkips() {
        let base  = parse(".22.")
        let layer = parse("....")
        let r     = SpriteComposer.compose(base: base, orderedLayers: [nil, layer, nil])
        XCTAssertEqual(r.rows, base.rows)   // layer is all-transparent → unchanged
    }
}

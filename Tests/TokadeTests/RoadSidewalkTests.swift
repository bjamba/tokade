@testable import Tokade
import XCTest

/// Covers the pure road-autotile edge-decision logic that drives sidewalk
/// placement (#100). Roads render a concrete curb on every outer edge — the
/// diamond sides facing a NON-road direction — so straights get sidewalks on
/// both flanks, corners wrap, and interior junction edges stay clean. The
/// rendering itself isn't unit-testable, but the which-edges decision is pure.
final class RoadSidewalkTests: XCTestCase {
    private typealias RA = IsoTileRenderer.RoadAutotile

    func testSidewalkEdgesIsolatedTileGetsAllFour() {
        // No road neighbors → curbs on every edge (#100).
        XCTAssertEqual(RA.sidewalkEdges(roadMask: 0), RA.all)
        XCTAssertEqual(RA.sidewalkEdges(roadMask: 0), 15)
    }

    func testSidewalkEdgesStraightHorizontalRoadGetsNorthAndSouth() {
        // Connects E + W → sidewalks only on N + S.
        let mask = RA.e | RA.w
        let edges = RA.sidewalkEdges(roadMask: mask)
        XCTAssertEqual(edges, RA.n | RA.s)
        XCTAssertNotEqual(edges & RA.e, RA.e)
        XCTAssertNotEqual(edges & RA.w, RA.w)
    }

    func testSidewalkEdgesStraightVerticalRoadGetsEastAndWest() {
        // Connects N + S → sidewalks only on E + W.
        let mask = RA.n | RA.s
        XCTAssertEqual(RA.sidewalkEdges(roadMask: mask), RA.e | RA.w)
    }

    func testSidewalkEdgesCornerWrapsTwoOuterEdges() {
        // L-curve connecting N + E → curbs on the two outer edges S + W,
        // wrapping the outer corner; the connected N/E edges stay clean.
        let mask = RA.n | RA.e
        let edges = RA.sidewalkEdges(roadMask: mask)
        XCTAssertEqual(edges, RA.s | RA.w)
        XCTAssertEqual(edges & RA.n, 0)
        XCTAssertEqual(edges & RA.e, 0)
    }

    func testSidewalkEdgesTJunctionGetsOnlyTheUnconnectedEdge() {
        // T connecting N + E + S → only the W edge gets a sidewalk.
        let mask = RA.n | RA.e | RA.s
        XCTAssertEqual(RA.sidewalkEdges(roadMask: mask), RA.w)
    }

    func testSidewalkEdgesFourWayJunctionHasNoOuterSidewalks() {
        // All four neighbors are road → no outer curbs at all (#100).
        XCTAssertEqual(RA.sidewalkEdges(roadMask: RA.all), 0)
    }

    func testSidewalkEdgesDeadEndGetsThreeEdges() {
        // A stub connecting only N → curbs on the other three edges.
        let edges = RA.sidewalkEdges(roadMask: RA.n)
        XCTAssertEqual(edges, RA.e | RA.s | RA.w)
        XCTAssertEqual(edges & RA.n, 0)
    }

    func testSidewalkEdgesIsExactComplementOfRoadMask() {
        // Property: a sidewalk edge exists iff there is no road in that
        // direction, for every possible 4-bit mask.
        for mask in 0...15 {
            let edges = RA.sidewalkEdges(roadMask: mask)
            XCTAssertEqual(edges, (~mask) & 0b1111)
            // Connected and sidewalk edges partition the four directions.
            XCTAssertEqual(edges & mask, 0)
            XCTAssertEqual(edges | mask, 0b1111)
        }
    }
}

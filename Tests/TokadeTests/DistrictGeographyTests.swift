@testable import Tokade
import XCTest

/// Issue #80, Phase 2a — pure geography algorithm (seed placement +
/// weighted growth ownership). Algorithm only; no rendering.
final class DistrictGeographyTests: XCTestCase {
    // MARK: - Helpers

    /// All-grass terrain of the given size (fully buildable + passable).
    private func grassGrid(_ size: Int) -> TerrainGrid {
        TerrainGrid(size: size, tiles: [TerrainTile](repeating: .grass, count: size * size))
    }

    private func district(loc: Int = 0, activity: Int = 0) -> TokeyoTownState.District {
        TokeyoTownState.District(
            id: "d", name: "d", rootSubpath: "", originLOC: loc,
            activityTokens: activity, lastActiveAt: nil
        )
    }

    // MARK: - placeSeeds

    func testPlaceSeedsIsDeterministic() {
        let grid = grassGrid(16)
        let a = DistrictGeography.placeSeeds(districtCount: 5, mapSize: 16, terrain: grid, townId: "town-xyz")
        let b = DistrictGeography.placeSeeds(districtCount: 5, mapSize: 16, terrain: grid, townId: "town-xyz")
        XCTAssertEqual(a.count, 5)
        XCTAssertEqual(a.map { [$0.x, $0.y] }, b.map { [$0.x, $0.y] })
    }

    func testPlaceSeedsDiffersByTownId() {
        let grid = grassGrid(16)
        let a = DistrictGeography.placeSeeds(districtCount: 5, mapSize: 16, terrain: grid, townId: "alpha")
        let b = DistrictGeography.placeSeeds(districtCount: 5, mapSize: 16, terrain: grid, townId: "beta")
        // The greedy spread can converge, but the first (PRNG) pick should
        // differ for different seeds, so at least one seed differs.
        XCTAssertNotEqual(a.map { [$0.x, $0.y] }, b.map { [$0.x, $0.y] })
    }

    func testPlaceSeedsLandOnPassableTiles() {
        // Mix water in so we can prove seeds avoid it.
        var tiles = [TerrainTile](repeating: .grass, count: 8 * 8)
        for i in 0 ..< 8 { tiles[i] = .water } // top row water
        for i in 0 ..< (8 * 8) where i % 8 == 0 { tiles[i] = .rock } // left column rock
        let grid = TerrainGrid(size: 8, tiles: tiles)
        let seeds = DistrictGeography.placeSeeds(districtCount: 5, mapSize: 8, terrain: grid, townId: "t")
        XCTAssertEqual(seeds.count, 5)
        for s in seeds {
            let tile = grid.tile(x: s.x, y: s.y)
            XCTAssertTrue(tile.isWalkable, "seed on impassable tile \(tile)")
            XCTAssertTrue(tile.isBuildable, "seed on non-buildable tile \(tile)")
        }
    }

    func testPlaceSeedsAreDistinctAndSpaced() {
        let grid = grassGrid(20)
        let seeds = DistrictGeography.placeSeeds(districtCount: 4, mapSize: 20, terrain: grid, townId: "spaced")
        XCTAssertEqual(seeds.count, 4)
        // Distinct.
        let keys = Set(seeds.map { $0.y * 20 + $0.x })
        XCTAssertEqual(keys.count, 4)
        // Spaced apart: minimum pairwise distance should be comfortably > 1
        // on a 20×20 open map (k-center greedy spreads them out).
        var minDist2 = Int.max
        for i in 0 ..< seeds.count {
            for j in (i + 1) ..< seeds.count {
                let dx = seeds[i].x - seeds[j].x
                let dy = seeds[i].y - seeds[j].y
                minDist2 = min(minDist2, dx * dx + dy * dy)
            }
        }
        XCTAssertGreaterThan(minDist2, 4, "seeds clustered too tightly")
    }

    func testPlaceSeedsNoLandReturnsEmpty() {
        let allWater = TerrainGrid(size: 4, tiles: [TerrainTile](repeating: .water, count: 16))
        XCTAssertTrue(DistrictGeography.placeSeeds(districtCount: 3, mapSize: 4, terrain: allWater, townId: "t").isEmpty)
    }

    // MARK: - ownership

    func testOwnershipSingleDistrictClaimsAllPassable() {
        var tiles = [TerrainTile](repeating: .grass, count: 6 * 6)
        tiles[0] = .water // one impassable tile
        let grid = TerrainGrid(size: 6, tiles: tiles)
        let owner = DistrictGeography.ownership(
            seeds: [(x: 3, y: 3)], weights: [5], mapSize: 6, terrain: grid
        )
        XCTAssertEqual(owner.count, 36)
        XCTAssertEqual(owner[0], -1, "impassable tile must be unowned")
        // Every passable tile claimed by district 0.
        for y in 0 ..< 6 {
            for x in 0 ..< 6 {
                let i = y * 6 + x
                if grid.tile(x: x, y: y).isWalkable {
                    XCTAssertEqual(owner[i], 0)
                } else {
                    XCTAssertEqual(owner[i], -1)
                }
            }
        }
    }

    func testOwnershipImpassableTilesAreUnowned() {
        // A vertical rock wall splits the map; tiles on the wall stay -1.
        var tiles = [TerrainTile](repeating: .grass, count: 7 * 7)
        for y in 0 ..< 7 { tiles[y * 7 + 3] = .rock }
        let grid = TerrainGrid(size: 7, tiles: tiles)
        let owner = DistrictGeography.ownership(
            seeds: [(x: 1, y: 3), (x: 5, y: 3)], weights: [1, 1], mapSize: 7, terrain: grid
        )
        for y in 0 ..< 7 {
            XCTAssertEqual(owner[y * 7 + 3], -1, "rock wall tile must be unowned")
        }
    }

    func testOwnershipHigherWeightClaimsStrictlyMore() {
        // Symmetric setup: two seeds equidistant from the map's interior,
        // identical terrain. The heavier district must own strictly more.
        let grid = grassGrid(21)
        let seeds = [(x: 5, y: 10), (x: 15, y: 10)]
        let owner = DistrictGeography.ownership(
            seeds: seeds, weights: [8, 1], mapSize: 21, terrain: grid
        )
        let count0 = owner.filter { $0 == 0 }.count
        let count1 = owner.filter { $0 == 1 }.count
        XCTAssertGreaterThan(count0, count1, "heavier district must claim more tiles")
        // Sanity: the lighter district still owns its own seed region.
        XCTAssertGreaterThan(count1, 0)
    }

    func testOwnershipPartitionsAllPassableTiles() {
        var tiles = [TerrainTile](repeating: .grass, count: 10 * 10)
        // Scatter some impassable tiles.
        tiles[0] = .water
        tiles[99] = .rock
        tiles[50] = .water
        let grid = TerrainGrid(size: 10, tiles: tiles)
        let owner = DistrictGeography.ownership(
            seeds: [(x: 2, y: 2), (x: 7, y: 7)], weights: [3, 5], mapSize: 10, terrain: grid
        )
        let passable = (0 ..< 100).filter { grid.tile(x: $0 % 10, y: $0 / 10).isWalkable }.count
        let assigned = owner.filter { $0 >= 0 }.count
        let unowned = owner.filter { $0 == -1 }.count
        // total assigned + unowned == passable tile count is not the identity;
        // unowned == (impassable + unreachable). Here all passable tiles are
        // reachable, so: assigned == passable, and assigned + (impassable) == n.
        XCTAssertEqual(assigned, passable)
        XCTAssertEqual(assigned + unowned, 100)
        XCTAssertEqual(unowned, 100 - passable)
    }

    func testOwnershipIsDeterministic() {
        let grid = grassGrid(15)
        let seeds = [(x: 3, y: 3), (x: 11, y: 11)]
        let a = DistrictGeography.ownership(seeds: seeds, weights: [4, 2], mapSize: 15, terrain: grid)
        let b = DistrictGeography.ownership(seeds: seeds, weights: [4, 2], mapSize: 15, terrain: grid)
        XCTAssertEqual(a, b)
    }

    // MARK: - weight

    func testWeightIsAtLeastOneAndMonotonicInActivity() {
        let cold = DistrictGeography.weight(for: district(loc: 0, activity: 0))
        XCTAssertGreaterThanOrEqual(cold, 1)
        let warm = DistrictGeography.weight(for: district(loc: 0, activity: 5000))
        XCTAssertGreaterThan(warm, cold, "activity must skew weight upward")
        // Monotonic in LOC base floor too.
        let small = DistrictGeography.weight(for: district(loc: 0, activity: 0))
        let big = DistrictGeography.weight(for: district(loc: 5000, activity: 0))
        XCTAssertGreaterThan(big, small)
    }

    func testWeightIsClampedAndNonNegativeInputs() {
        // Huge inputs are clamped (no single district dominates).
        let huge = DistrictGeography.weight(for: district(loc: 10_000_000, activity: 10_000_000))
        XCTAssertLessThanOrEqual(huge, 1 + 8 + 24)
        // Negative inputs are floored, never below 1.
        let neg = DistrictGeography.weight(for: district(loc: -100, activity: -100))
        XCTAssertGreaterThanOrEqual(neg, 1)
    }
}

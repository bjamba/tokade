@testable import Tokade
import XCTest

/// #52 — L-road routing can orphan a building behind water, leaving its
/// only goal unreachable. A* then returns an empty path; the old AI left
/// the npc pointing at the dead goal with no route and replanned to the
/// same unreachable destination forever, freezing the townsfolk in place.
/// These tests pin the recovery behavior: an unreachable goal must not
/// produce a permanent dead empty path.
final class TownsfolkPathingTests: XCTestCase {
    /// Only-goal-unreachable: a single building walled off by water. The
    /// townsfolk must not get stuck holding the unreachable goal — after
    /// the planning tick it should have retargeted to a reachable tile
    /// (here, where it stands) so subsequent ticks keep cycling instead of
    /// freezing on a dead empty path.
    func testTownsfolkRecoversWhenOnlyGoalIsUnreachable() {
        // 3x3 all water except a lone grass tile at (0, 0) where the npc
        // stands, and the goal building at (2, 2) — fully surrounded by
        // water, so A* can never reach it.
        var tiles = [TerrainTile](repeating: .water, count: 3 * 3)
        tiles[0 * 3 + 0] = .grass
        let grid = TerrainGrid(size: 3, tiles: tiles)

        let unreachable = TokeyoTownState.PlacedBuilding(
            id: UUID(), kind: "plain-cottage",
            tileX: 2, tileY: 2, width: 1, height: 1,
            placedAt: .now
        )
        let npc = TokeyoTownState.Townsfolk(
            id: UUID(), name: "T",
            tileX: 0, tileY: 0,
            homeBuildingId: nil,
            goalX: 0, goalY: 0,
            pauseRemaining: 0,
            activity: "test",
            hue: 0.5,
            createdAt: .now
        )

        // Plan tick: A* to the walled-off building returns empty.
        var stepped = TownsfolkAI.step(townsfolk: [npc],
                                       buildings: [unreachable],
                                       terrain: grid, mapSize: 3)
        // No phantom route, and the goal was retargeted to a tile we can
        // actually stand on — not left pointing at the unreachable building.
        XCTAssertTrue(stepped[0].pathKeys.isEmpty)
        XCTAssertFalse(stepped[0].goalX == unreachable.tileX
            && stepped[0].goalY == unreachable.tileY)
        XCTAssertEqual(stepped[0].goalX, 0)
        XCTAssertEqual(stepped[0].goalY, 0)

        // Step many more ticks (clearing any random pause each time). The
        // npc must never end up permanently "not at goal with an empty
        // path" — that is the frozen state from #52. Here it stays on its
        // grass tile, re-picking the unreachable errand and re-recovering.
        for _ in 0..<25 {
            stepped[0].pauseRemaining = 0
            stepped = TownsfolkAI.step(townsfolk: stepped,
                                       buildings: [unreachable],
                                       terrain: grid, mapSize: 3)
            let cur = stepped[0]
            let curX = Int(cur.tileX.rounded())
            let curY = Int(cur.tileY.rounded())
            let atGoal = curX == cur.goalX && curY == cur.goalY
            // The freeze signature is: stranded mid-trip (not at goal) with
            // no route to follow. Recovery guarantees we're never both.
            XCTAssertFalse(!atGoal && cur.pathKeys.isEmpty,
                           "townsfolk froze: not at goal with no path (#52)")
        }
    }

    /// A reachable building still routes normally even when an unreachable
    /// one is present — recovery doesn't break the happy path. With the
    /// reachable goal walled off only some of the time, repeated ticks must
    /// eventually produce real motion toward it.
    func testTownsfolkStillRoutesToAReachableBuilding() {
        // North row walkable corridor; everything else water. Reachable
        // building at the east end, plus an unreachable one off in water.
        var tiles = [TerrainTile](repeating: .water, count: 4 * 4)
        for x in 0..<4 { tiles[0 * 4 + x] = .grass }
        let grid = TerrainGrid(size: 4, tiles: tiles)

        let reachable = TokeyoTownState.PlacedBuilding(
            id: UUID(), kind: "plain-cottage",
            tileX: 3, tileY: 0, width: 1, height: 1,
            placedAt: .now
        )
        let unreachable = TokeyoTownState.PlacedBuilding(
            id: UUID(), kind: "plain-cottage",
            tileX: 2, tileY: 3, width: 1, height: 1,
            placedAt: .now
        )
        let npc = TokeyoTownState.Townsfolk(
            id: UUID(), name: "T",
            tileX: 0, tileY: 0,
            homeBuildingId: nil,
            goalX: 0, goalY: 0,
            pauseRemaining: 0,
            activity: "test",
            hue: 0.5,
            createdAt: .now
        )

        var stepped = [npc]
        var sawMotion = false
        for _ in 0..<40 {
            stepped[0].pauseRemaining = 0
            stepped = TownsfolkAI.step(townsfolk: stepped,
                                       buildings: [reachable, unreachable],
                                       terrain: grid, mapSize: 4)
            if !stepped[0].pathKeys.isEmpty || stepped[0].nextStep != nil {
                sawMotion = true
            }
        }
        XCTAssertTrue(sawMotion,
                      "npc should still route to the reachable building")
    }
}

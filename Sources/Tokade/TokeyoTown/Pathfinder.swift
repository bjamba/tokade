import Foundation

/// A* on the tile grid. Cardinal neighbours only (no diagonals).
/// Roads cost ~1, grass ~12, trees ~18 — so when both options are
/// available the search routes through roads naturally, without
/// hand-tuning per-tick heuristics like the v3.5 greedy AI did.
///
/// Buildings are impassable except for the goal — townsfolk can step
/// into the *destination* tile but won't cross through other buildings.
/// Cliff transitions of more than one elevation tier are also blocked.
enum Pathfinder {
    /// Returns the sequence of tiles from (immediately after) `start` to
    /// `goal`, inclusive of `goal`. Empty if no path exists.
    static func path(
        from start: (x: Int, y: Int),
        to goal: (x: Int, y: Int),
        terrain: TerrainGrid,
        buildings: [TokeyoTownState.PlacedBuilding],
        mapSize: Int
    ) -> [(x: Int, y: Int)] {
        if start.x == goal.x, start.y == goal.y { return [] }

        // Pre-compute occupied building tiles so we can reject them in O(1).
        var blocked = Set<Int>()
        for b in buildings {
            for dy in 0..<b.height {
                for dx in 0..<b.width {
                    blocked.insert((b.tileY + dy) * mapSize + (b.tileX + dx))
                }
            }
        }
        // The goal tile is allowed even if it's a building footprint.
        blocked.remove(goal.y * mapSize + goal.x)

        // Open set / closed set + bookkeeping. Frontier is a simple
        // sorted-array priority queue; for ≤2,304 tiles it's plenty fast.
        struct Frontier {
            var items: [(node: Int, f: Int)] = []
            mutating func push(_ node: Int, f: Int) {
                let i = items.firstIndex(where: { $0.f > f }) ?? items.count
                items.insert((node, f), at: i)
            }

            mutating func pop() -> Int? {
                items.isEmpty ? nil : items.removeFirst().node
            }
        }

        var frontier = Frontier()
        var cameFrom: [Int: Int] = [:]
        var gScore: [Int: Int] = [:]

        let startKey = start.y * mapSize + start.x
        let goalKey = goal.y * mapSize + goal.x
        gScore[startKey] = 0
        frontier.push(startKey, f: heuristic(start, goal))

        while let currentKey = frontier.pop() {
            if currentKey == goalKey {
                return reconstruct(cameFrom: cameFrom, from: startKey,
                                   to: goalKey, mapSize: mapSize)
            }
            let cx = currentKey % mapSize
            let cy = currentKey / mapSize
            let currentG = gScore[currentKey] ?? Int.max
            let currentElev = terrain.elev(x: cx, y: cy)

            for (nx, ny) in [
                (cx + 1, cy), (cx - 1, cy),
                (cx, cy + 1), (cx, cy - 1),
            ] {
                guard nx >= 0, ny >= 0, nx < mapSize, ny < mapSize else { continue }
                let key = ny * mapSize + nx
                let tile = terrain.tile(x: nx, y: ny)
                if !tile.isWalkable { continue }
                if blocked.contains(key) { continue }
                if abs(terrain.elev(x: nx, y: ny) - currentElev) > 1 { continue }
                let stepCost = tile.pathCost
                let tentativeG = currentG + stepCost
                if tentativeG < (gScore[key] ?? Int.max) {
                    cameFrom[key] = currentKey
                    gScore[key] = tentativeG
                    let f = tentativeG + heuristic((nx, ny), goal) * tile.pathCost
                    frontier.push(key, f: f)
                }
            }
        }
        return []  // no path
    }

    /// Manhattan distance. Admissible for the grid; multiplied by a
    /// tile's pathCost in the f-score so road-routed paths win when
    /// distances tie.
    private static func heuristic(_ a: (Int, Int), _ b: (Int, Int)) -> Int {
        abs(a.0 - b.0) + abs(a.1 - b.1)
    }

    private static func reconstruct(
        cameFrom: [Int: Int],
        from start: Int,
        to goal: Int,
        mapSize: Int
    ) -> [(x: Int, y: Int)] {
        var steps: [(Int, Int)] = []
        var key = goal
        while key != start {
            let x = key % mapSize
            let y = key / mapSize
            steps.append((x, y))
            guard let prev = cameFrom[key] else { break }
            key = prev
        }
        return steps.reversed()
    }
}

import Foundation

/// Townsfolk simulation. Each tick advances every townsfolk one step along
/// their current path, picks a new errand when they arrive, pauses for a
/// few seconds "inside" a building, then heads somewhere else. Roads
/// reduce movement friction (preferred when picking the next step).
///
/// Pathing is intentionally cheap — pick the next neighbor tile that
/// minimizes a weighted Manhattan distance to the goal. Good enough for
/// a cozy game; no A* needed.
enum TownsfolkAI {
    /// Tick step (seconds of "in-game time" that the AI applies per call).
    /// Calibrated against the 3s background tick + ~60Hz foreground frame.
    static let tickSeconds: Double = 1.0

    /// Probability that an idle (just-arrived) townsfolk lingers at the
    /// destination before picking a new goal — gives them a sense of
    /// "doing something there."
    static let pauseChance: Double = 0.85
    /// Range of pause durations in tick-seconds.
    static let pauseRange: ClosedRange<Double> = 3...10

    static func step(
        townsfolk: [TokeyoTownState.Townsfolk],
        buildings: [TokeyoTownState.PlacedBuilding],
        terrain: TerrainGrid,
        mapSize: Int
    ) -> [TokeyoTownState.Townsfolk] {
        guard !townsfolk.isEmpty else { return townsfolk }
        return townsfolk.map { npc in
            stepOne(
                npc: npc,
                buildings: buildings,
                terrain: terrain,
                mapSize: mapSize
            )
        }
    }

    private static func stepOne(
        npc: TokeyoTownState.Townsfolk,
        buildings: [TokeyoTownState.PlacedBuilding],
        terrain: TerrainGrid,
        mapSize: Int
    ) -> TokeyoTownState.Townsfolk {
        var n = npc

        // Paused → just decrement.
        if n.pauseRemaining > 0 {
            n.pauseRemaining = max(0, n.pauseRemaining - tickSeconds)
            return n
        }

        let atGoal = abs(n.tileX - Double(n.goalX)) < 0.5 &&
            abs(n.tileY - Double(n.goalY)) < 0.5

        if atGoal {
            // Decide what to do next.
            return pickNewErrand(npc: n, buildings: buildings, terrain: terrain, mapSize: mapSize)
        }

        // Step toward goal — pick neighbor that minimizes the heuristic,
        // preferring road tiles (lower pathCost) when scores are close.
        return advance(npc: n, terrain: terrain, mapSize: mapSize)
    }

    private static func pickNewErrand(
        npc: TokeyoTownState.Townsfolk,
        buildings: [TokeyoTownState.PlacedBuilding],
        terrain: TerrainGrid,
        mapSize: Int
    ) -> TokeyoTownState.Townsfolk {
        var n = npc

        // Pause first (most of the time).
        if Double.random(in: 0..<1) < pauseChance {
            n.pauseRemaining = Double.random(in: pauseRange)
        }

        // Pick a goal:
        //   - if homeless, hang out at a random walkable tile
        //   - if at home, head to a random non-home building (or random tile
        //     if no other buildings exist)
        //   - if elsewhere, head home
        let home = buildings.first(where: { $0.id == npc.homeBuildingId })
        let isAtHome = home.map { h in
            (Int(npc.tileX.rounded()) >= h.tileX) &&
                (Int(npc.tileX.rounded()) < h.tileX + h.width) &&
                (Int(npc.tileY.rounded()) >= h.tileY) &&
                (Int(npc.tileY.rounded()) < h.tileY + h.height)
        } ?? false

        if home == nil {
            // Wander.
            if let pos = randomWalkableTile(terrain: terrain, mapSize: mapSize) {
                n.goalX = pos.x
                n.goalY = pos.y
                n.activity = "wandering"
            }
            return n
        }

        if isAtHome {
            // Pick a destination building (not home), or fall back to wander.
            let destinations = buildings.filter { $0.id != home?.id }
            if let dest = destinations.randomElement() {
                n.goalX = dest.tileX
                n.goalY = dest.tileY
                n.activity = activityLabel(for: dest)
            } else if let pos = randomWalkableTile(terrain: terrain, mapSize: mapSize) {
                n.goalX = pos.x
                n.goalY = pos.y
                n.activity = "wandering"
            }
        } else {
            // Head home.
            if let h = home {
                n.goalX = h.tileX
                n.goalY = h.tileY
                n.activity = "going home"
            }
        }
        return n
    }

    private static func activityLabel(for building: TokeyoTownState.PlacedBuilding) -> String {
        guard let b = BuildingCatalog.find(building.kind) else { return "errand" }
        return "visiting \(b.displayName)"
    }

    /// One AI step = one full cardinal hop. The renderer interpolates
    /// over phase ∈ [0, 1) between `(tileX, tileY)` and `nextStep`, so
    /// motion is strictly N/E/S/W on-screen — no diagonals.
    private static func advance(
        npc: TokeyoTownState.Townsfolk,
        terrain: TerrainGrid,
        mapSize: Int
    ) -> TokeyoTownState.Townsfolk {
        var n = npc
        // Snap to whatever nextStep we previously committed to.
        if let step = n.nextStep {
            n.tileX = Double(step.0)
            n.tileY = Double(step.1)
        }
        n.nextStepX = nil
        n.nextStepY = nil

        let curX = Int(n.tileX.rounded())
        let curY = Int(n.tileY.rounded())
        if curX == n.goalX, curY == n.goalY {
            // Already at goal; the planner will pick a new errand next tick.
            return n
        }

        let candidates: [(x: Int, y: Int)] = [
            (curX + 1, curY), (curX - 1, curY),
            (curX, curY + 1), (curX, curY - 1),
        ]
        var best: (x: Int, y: Int)?
        var bestScore = Double.greatestFiniteMagnitude
        for c in candidates {
            guard c.x >= 0, c.x < mapSize, c.y >= 0, c.y < mapSize else { continue }
            let tile = terrain.tile(x: c.x, y: c.y)
            guard tile.isWalkable else { continue }
            // Cliff-friction: prefer steps where the elevation delta is ≤1.
            let elevDelta = abs(terrain.elev(x: c.x, y: c.y) - terrain.elev(x: curX, y: curY))
            if elevDelta > 1 { continue }
            let dx = Double(c.x - n.goalX)
            let dy = Double(c.y - n.goalY)
            let score = abs(dx) + abs(dy) + Double(tile.pathCost) * 0.04
            if score < bestScore {
                bestScore = score
                best = c
            }
        }
        if let next = best {
            n.nextStepX = next.x
            n.nextStepY = next.y
        } else {
            n.pauseRemaining = 2
            n.activity = "stuck"
        }
        return n
    }

    private static func randomWalkableTile(terrain: TerrainGrid, mapSize: Int) -> (x: Int, y: Int)? {
        for _ in 0..<24 {
            let x = Int.random(in: 0..<mapSize)
            let y = Int.random(in: 0..<mapSize)
            if terrain.tile(x: x, y: y).isWalkable { return (x, y) }
        }
        return nil
    }
}

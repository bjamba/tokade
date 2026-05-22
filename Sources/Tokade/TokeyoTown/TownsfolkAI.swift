import Foundation

/// Townsfolk simulation. v3.12 — building-to-building A* pathing.
///
/// Each tick:
///   - If paused, decrement.
///   - If at goal, pick a new building destination + precompute the
///     full A* path to it. Pause briefly to read as "visiting."
///   - Else, advance: pop the next step off the stored path, write it
///     into `nextStep`. The renderer interpolates current → nextStep
///     using the elapsed-since-last-tick phase.
///
/// All destinations are buildings (never random tiles). If a path
/// becomes invalid (player builds on it, or the destination is
/// demolished), the npc clears it and re-plans next tick.
enum TownsfolkAI {
    static let tickSeconds: Double = 1.0
    static let pauseChance: Double = 0.85
    static let pauseRange: ClosedRange<Double> = 3 ... 10

    static func step(
        townsfolk: [TokeyoTownState.Townsfolk],
        buildings: [TokeyoTownState.PlacedBuilding],
        terrain: TerrainGrid,
        mapSize: Int
    ) -> [TokeyoTownState.Townsfolk] {
        guard !townsfolk.isEmpty else { return townsfolk }
        return townsfolk.map { npc in
            stepOne(npc: npc, buildings: buildings,
                    terrain: terrain, mapSize: mapSize)
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

        // Snap to the previously-committed nextStep.
        if let step = n.nextStep {
            n.tileX = Double(step.0)
            n.tileY = Double(step.1)
            n.nextStepX = nil
            n.nextStepY = nil
        }

        let curX = Int(n.tileX.rounded())
        let curY = Int(n.tileY.rounded())
        let atGoal = curX == n.goalX && curY == n.goalY

        if atGoal || n.pathKeys.isEmpty {
            return pickNewErrand(npc: n, buildings: buildings,
                                 terrain: terrain, mapSize: mapSize)
        }

        // Consume next step from the precomputed path.
        let nextKey = n.pathKeys.removeFirst()
        n.nextStepX = nextKey % mapSize
        n.nextStepY = nextKey / mapSize
        return n
    }

    private static func pickNewErrand(
        npc: TokeyoTownState.Townsfolk,
        buildings: [TokeyoTownState.PlacedBuilding],
        terrain: TerrainGrid,
        mapSize: Int
    ) -> TokeyoTownState.Townsfolk {
        var n = npc
        // 85% pause on arrival.
        if Double.random(in: 0 ..< 1) < pauseChance {
            n.pauseRemaining = Double.random(in: pauseRange)
        }

        guard !buildings.isEmpty else {
            // No buildings yet — stay put. The renderer will hold the npc
            // in place until something gets placed.
            n.pathKeys = []
            return n
        }

        // Pick a destination *building*. Prefer home if not at home,
        // otherwise any non-home building, fall back to "any building".
        let home = buildings.first(where: { $0.id == npc.homeBuildingId })
        let curX = Int(n.tileX.rounded())
        let curY = Int(n.tileY.rounded())
        let isAtHome = home.map { h in
            (curX >= h.tileX) && (curX < h.tileX + h.width) &&
                (curY >= h.tileY) && (curY < h.tileY + h.height)
        } ?? false

        let destination: TokeyoTownState.PlacedBuilding
        if isAtHome {
            let candidates = buildings.filter { $0.id != home?.id }
            destination = candidates.randomElement() ?? buildings.randomElement()!
            n.activity = activityLabel(for: destination)
        } else if let h = home {
            destination = h
            n.activity = "going home"
        } else {
            destination = buildings.randomElement()!
            n.activity = activityLabel(for: destination)
        }

        let goal = (x: destination.tileX, y: destination.tileY)
        n.goalX = goal.x
        n.goalY = goal.y

        // A* — full route precomputed in one shot.
        let path = Pathfinder.path(
            from: (curX, curY),
            to: goal,
            terrain: terrain,
            buildings: buildings,
            mapSize: mapSize
        )
        n.pathKeys = path.map { $0.y * mapSize + $0.x }
        return n
    }

    private static func activityLabel(for building: TokeyoTownState.PlacedBuilding) -> String {
        guard let b = BuildingCatalog.find(building.kind) else { return "errand" }
        return "visiting \(b.displayName)"
    }
}

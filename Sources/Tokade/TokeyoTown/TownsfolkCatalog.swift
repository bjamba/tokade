import Foundation

/// Per-biome name pools for the procedurally-generated townsfolk.
enum TownsfolkCatalog {
    static func names(for biome: TokeyoTownState.Biome) -> [String] {
        switch biome {
        case .plain:
            return ["Mio", "Theo", "Wren", "Juno", "Cleo", "Otis", "Pia", "Roan",
                    "Sage", "Tova", "Ezra", "Lin"]
        case .desert:
            return ["Amira", "Hadi", "Layla", "Saif", "Zara", "Omar", "Yara", "Idris",
                    "Nour", "Tahir", "Salma", "Karim"]
        case .tundra:
            return ["Sven", "Mika", "Ingrid", "Aki", "Lars", "Yuki", "Tuomas", "Saga",
                    "Rune", "Eira", "Alma", "Niko"]
        case .forest:
            return ["Hana", "Kai", "Lila", "Soren", "Nori", "Aine", "Bram", "Rin",
                    "Asa", "Pip", "Mei", "Finn"]
        case .beach:
            return ["Akira", "Mahina", "Kalei", "Noa", "Iris", "Tama", "Mira", "Leo",
                    "Wave", "Kona", "Nao", "Sol"]
        }
    }
}

/// Spawns and home-assigns townsfolk. v2 — placement honors terrain
/// (won't spawn on water/rock/tree) and tries to assign every townsfolk
/// a home building when one is available.
enum TownsfolkSpawner {
    static func spawn(
        count: Int,
        biome: TokeyoTownState.Biome,
        terrain: TerrainGrid,
        now: Date = .now
    ) -> [TokeyoTownState.Townsfolk] {
        let pool = TownsfolkCatalog.names(for: biome)
        var out: [TokeyoTownState.Townsfolk] = []
        for _ in 0..<count {
            guard let tile = randomWalkableTile(terrain: terrain) else { continue }
            out.append(TokeyoTownState.Townsfolk(
                id: UUID(),
                name: pool.randomElement() ?? "Sam",
                tileX: Double(tile.x),
                tileY: Double(tile.y),
                homeBuildingId: nil,
                goalX: tile.x,
                goalY: tile.y,
                pauseRemaining: Double.random(in: 0..<3),
                activity: "wandering",
                hue: Double.random(in: 0..<1),
                createdAt: now
            ))
        }
        return out
    }

    static func spawnOne(
        biome: TokeyoTownState.Biome,
        terrain: TerrainGrid,
        home: TokeyoTownState.PlacedBuilding,
        now: Date = .now
    ) -> TokeyoTownState.Townsfolk? {
        _ = terrain
        let pool = TownsfolkCatalog.names(for: biome)
        return TokeyoTownState.Townsfolk(
            id: UUID(),
            name: pool.randomElement() ?? "Sam",
            tileX: Double(home.tileX),
            tileY: Double(home.tileY),
            homeBuildingId: home.id,
            goalX: home.tileX,
            goalY: home.tileY,
            pauseRemaining: 0,
            activity: "moving in",
            hue: Double.random(in: 0..<1),
            createdAt: now
        )
    }

    /// Give homeless townsfolk a roof when one becomes available. Each new
    /// home houses at most one townsfolk.
    static func assignHomeIfNeeded(
        _ folk: [TokeyoTownState.Townsfolk],
        to home: TokeyoTownState.PlacedBuilding
    ) -> [TokeyoTownState.Townsfolk] {
        guard let idx = folk.firstIndex(where: { $0.homeBuildingId == nil }) else { return folk }
        var copy = folk
        copy[idx].homeBuildingId = home.id
        copy[idx].activity = "settling in"
        return copy
    }

    private static func randomWalkableTile(terrain: TerrainGrid) -> (x: Int, y: Int)? {
        for _ in 0..<32 {
            let x = Int.random(in: 0..<terrain.size)
            let y = Int.random(in: 0..<terrain.size)
            if terrain.tile(x: x, y: y).isWalkable { return (x, y) }
        }
        for y in 0..<terrain.size {
            for x in 0..<terrain.size where terrain.tile(x: x, y: y).isWalkable {
                return (x, y)
            }
        }
        return nil
    }
}

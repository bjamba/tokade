import Foundation

/// Per-biome name pools for the procedurally-generated townsfolk. Names are
/// short, cozy, and intentionally a mix of cultures — every Tokeyo Town
/// should feel like somewhere small and welcoming. Add more freely.
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

    static func spawnTownsfolk(
        count: Int,
        biome: TokeyoTownState.Biome,
        mapSize: Int,
        now: Date = .now
    ) -> [TokeyoTownState.Townsfolk] {
        let pool = names(for: biome)
        return (0..<count).map { _ in
            let x = Int.random(in: 0..<mapSize)
            let y = Int.random(in: 0..<mapSize)
            return TokeyoTownState.Townsfolk(
                id: UUID(),
                name: pool.randomElement() ?? "Sam",
                tileX: Double(x),
                tileY: Double(y),
                goalX: Int.random(in: 0..<mapSize),
                goalY: Int.random(in: 0..<mapSize),
                hue: Double.random(in: 0..<1),
                createdAt: now
            )
        }
    }
}

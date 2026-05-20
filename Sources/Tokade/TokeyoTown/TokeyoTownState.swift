import Foundation

/// Persisted state for one Tokeyo Town. One file per town, one town active
/// at a time in MVP. See docs/adr/0006-tokeyo-town-architecture.md.
struct TokeyoTownState: Codable, Equatable {
    var schemaVersion: Int = 2
    var townId: String
    var createdAt: Date
    var lastTickAt: Date

    var repo: RepoSnapshot
    var resources: Resources
    var accountedEvents: AccountedEvents
    var buildings: [PlacedBuilding]
    var townsfolk: [Townsfolk]
    /// v2+ — procedurally generated landscape. Old saves decode with the
    /// fallback below in `init(from:)`.
    var terrain: TerrainGrid

    init(
        schemaVersion: Int = 2,
        townId: String,
        createdAt: Date,
        lastTickAt: Date,
        repo: RepoSnapshot,
        resources: Resources,
        accountedEvents: AccountedEvents,
        buildings: [PlacedBuilding],
        townsfolk: [Townsfolk],
        terrain: TerrainGrid
    ) {
        self.schemaVersion = schemaVersion
        self.townId = townId
        self.createdAt = createdAt
        self.lastTickAt = lastTickAt
        self.repo = repo
        self.resources = resources
        self.accountedEvents = accountedEvents
        self.buildings = buildings
        self.townsfolk = townsfolk
        self.terrain = terrain
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, townId, createdAt, lastTickAt, repo, resources,
             accountedEvents, buildings, townsfolk, terrain
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        townId = try c.decode(String.self, forKey: .townId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lastTickAt = try c.decode(Date.self, forKey: .lastTickAt)
        repo = try c.decode(RepoSnapshot.self, forKey: .repo)
        resources = try c.decode(Resources.self, forKey: .resources)
        accountedEvents = try c.decode(AccountedEvents.self, forKey: .accountedEvents)
        buildings = try c.decode([PlacedBuilding].self, forKey: .buildings)
        townsfolk = try c.decode([Townsfolk].self, forKey: .townsfolk)
        if let t = try c.decodeIfPresent(TerrainGrid.self, forKey: .terrain) {
            terrain = t
        } else {
            // v1 save with no terrain → regenerate from the townId seed
            // and the repo's map size. Same townId always gives the
            // same terrain, so re-opening an old town is stable.
            terrain = TerrainGenerator.generate(
                seed: TerrainGenerator.seed(for: townId),
                size: repo.mapSize,
                biome: repo.biome
            )
        }
    }

    struct RepoSnapshot: Codable, Equatable {
        var path: String
        var displayName: String
        var scannedAt: Date
        var primaryLanguage: String
        var biome: Biome
        var era: Era
        var ageInDays: Int
        var loc: Int
        var mapSize: Int
        var contributorCount: Int
        var lushness: Double
    }

    struct Resources: Codable, Equatable, Hashable {
        var coin: Int = 0
        var knowledge: Int = 0
        var lumber: Int = 0
        var industry: Int = 0
        var stability: Int = 0
        var inspiration: Int = 0
        var growth: Int = 0

        static let zero = Resources()

        mutating func add(_ other: Resources) {
            coin += other.coin
            knowledge += other.knowledge
            lumber += other.lumber
            industry += other.industry
            stability += other.stability
            inspiration += other.inspiration
            growth += other.growth
        }

        mutating func deduct(_ cost: Resources) -> Bool {
            guard canAfford(cost) else { return false }
            coin -= cost.coin
            knowledge -= cost.knowledge
            lumber -= cost.lumber
            industry -= cost.industry
            stability -= cost.stability
            inspiration -= cost.inspiration
            growth -= cost.growth
            return true
        }

        func canAfford(_ cost: Resources) -> Bool {
            coin >= cost.coin &&
            knowledge >= cost.knowledge &&
            lumber >= cost.lumber &&
            industry >= cost.industry &&
            stability >= cost.stability &&
            inspiration >= cost.inspiration &&
            growth >= cost.growth
        }
    }

    struct AccountedEvents: Codable, Equatable {
        var lastEventId: String?
        var lastTimestamp: Date?
    }

    struct PlacedBuilding: Codable, Equatable, Identifiable {
        var id: UUID
        var kind: String
        var tileX: Int
        var tileY: Int
        /// Footprint width/height in tiles. v2 — defaults to 1 for old saves.
        var width: Int = 1
        var height: Int = 1
        var placedAt: Date
    }

    struct Townsfolk: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var tileX: Double
        var tileY: Double
        /// Home building. May be nil if the townsfolk hasn't been
        /// assigned one yet (no houses placed).
        var homeBuildingId: UUID?
        /// Current goal tile they're walking toward. Updated by the
        /// errand planner — see `TownsfolkAI`.
        var goalX: Int
        var goalY: Int
        /// Seconds remaining to pause at the current tile (e.g. while
        /// "inside" a destination building). Decremented each tick.
        var pauseRemaining: Double = 0
        /// Activity label — drives a one-line status line if we ever
        /// surface it ("visiting Bakery", "going home").
        var activity: String = "wandering"
        var hue: Double
        var createdAt: Date
    }

    enum Biome: String, Codable, CaseIterable {
        case plain, desert, tundra, forest, beach
    }

    enum Era: String, Codable, CaseIterable {
        case modern, contemporary, classical
    }

    static func fresh(townId: String, repo: RepoSnapshot, now: Date = .now) -> TokeyoTownState {
        let terrain = TerrainGenerator.generate(
            seed: TerrainGenerator.seed(for: townId),
            size: repo.mapSize,
            biome: repo.biome
        )
        return TokeyoTownState(
            townId: townId,
            createdAt: now,
            lastTickAt: now,
            repo: repo,
            resources: .zero,
            accountedEvents: .init(),
            buildings: [],
            townsfolk: [],
            terrain: terrain
        )
    }
}

/// Index file at `~/.tokade/games/tokeyotown/index.json`. Maps townIds →
/// metadata so we can list towns and find the active one.
struct TokeyoTownIndex: Codable, Equatable {
    var schemaVersion: Int = 1
    var activeTownId: String?
    var towns: [Entry]

    struct Entry: Codable, Equatable, Identifiable {
        var id: String { townId }
        var townId: String
        var displayName: String
        var repoPath: String
        var biome: TokeyoTownState.Biome
        var lastOpenedAt: Date
    }

    static let empty = TokeyoTownIndex(activeTownId: nil, towns: [])
}

import Foundation

/// Persisted state for one Tokeyo Town. One file per town, one town active
/// at a time in MVP. See docs/adr/0006-tokeyo-town-architecture.md.
struct TokeyoTownState: Codable, Equatable {
    var schemaVersion: Int = 1
    var townId: String
    var createdAt: Date
    var lastTickAt: Date

    var repo: RepoSnapshot
    var resources: Resources
    var accountedEvents: AccountedEvents
    var buildings: [PlacedBuilding]
    var townsfolk: [Townsfolk]

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
        var placedAt: Date
    }

    struct Townsfolk: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var tileX: Double
        var tileY: Double
        var goalX: Int
        var goalY: Int
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
        TokeyoTownState(
            townId: townId,
            createdAt: now,
            lastTickAt: now,
            repo: repo,
            resources: .zero,
            accountedEvents: .init(),
            buildings: [],
            townsfolk: []
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

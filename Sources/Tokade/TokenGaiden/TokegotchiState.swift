import Foundation

/// Persistent state for one Tokegotchi save. Lives at
/// `~/.tokade/games/tokegotchi.json` (file mode 0600). When the active
/// Tokegotchi dies, it rolls into `bloodline.ancestors` for the next gen.
struct TokegotchiState: Codable, Equatable {
    var schemaVersion: Int = 1
    var identity: Identity
    var vitals: Vitals
    var progress: Progress
    var world: World
    var inventory: Inventory
    var bloodline: Bloodline

    struct Identity: Codable, Equatable {
        var name: String
        var generation: Int
        var bornAt: Date
        /// Accumulated weighted token count. The lifespan threshold is
        /// stored separately so quest-derived extensions can grow it.
        var ageTokens: Int
        var lifespanTokens: Int
        var appearance: Appearance
    }

    struct Appearance: Codable, Equatable {
        var skinSwatch: String       // e.g. "lavender"
        var irisSwatch: String       // e.g. "blue"
        var hairStyle: String        // e.g. "horns"
        var hairSwatch: String       // e.g. "ivory"
    }

    struct Vitals: Codable, Equatable {
        var hp: Int
        var sp: Int
        var stats: Stats

        /// Derived per ADR-0005: 80 + (STR + DEX) × 2.
        var hpMax: Int { 80 + (stats.str + stats.dex) * 2 }
        /// Derived per ADR-0005: 40 + (INT + CHA) × 2.
        var spMax: Int { 40 + (stats.int + stats.cha) * 2 }

        mutating func clamp() {
            hp = max(0, min(hp, hpMax))
            sp = max(0, min(sp, spMax))
        }
    }

    struct Stats: Codable, Equatable {
        var str: Int
        var dex: Int
        var int: Int
        var agi: Int
        var cha: Int

        static let starter = Stats(str: 5, dex: 5, int: 5, agi: 5, cha: 5)
    }

    struct Progress: Codable, Equatable {
        var exp: Int
        var gold: Int
    }

    struct World: Codable, Equatable {
        var currentRegion: String?            // cwd-prefix identifying current region
        var reputation: [String: Int]         // region → 0–100
    }

    struct Inventory: Codable, Equatable {
        var items: [String: Int]              // itemId → count
        var equippedCosmetic: [String: String?]
        var equippedGear: [String: String?]
        var skillsLearned: [String]
        var activeQuests: [String]
    }

    struct Bloodline: Codable, Equatable {
        var ancestors: [Ancestor]
    }

    struct Ancestor: Codable, Equatable {
        var name: String
        var generation: Int
        var peakStats: Stats
        var ageTokensAtDeath: Int
        var daysLived: Int
        var causeOfDeath: CauseOfDeath
        var bornAt: Date
        var diedAt: Date
    }

    enum CauseOfDeath: String, Codable, Equatable {
        case natural        // age reached lifespan
        case hpZero         // killed in critical state
    }

    /// Whether the pet's age has reached its lifespan.
    var isAgedOut: Bool {
        identity.ageTokens >= identity.lifespanTokens
    }

    /// Whether the pet has hit HP=0 (enters Critical state).
    var isCritical: Bool {
        vitals.hp <= 0
    }
}

extension TokegotchiState {
    /// Build a new starter pet from a chosen appearance + name. Called once
    /// at character creation or on the first launch after a permanent death.
    static func newStarter(
        name: String,
        appearance: Appearance,
        generation: Int = 1,
        bornAt: Date = Date(),
        inheritedStats: Stats? = nil,
        ancestors: [Ancestor] = [],
        carriedItems: [String: Int] = [:],
        carriedCosmetic: [String: String?] = [:],
        carriedReputation: [String: Int] = [:]
    ) -> TokegotchiState {
        let stats = inheritedStats ?? Stats.starter
        var vitals = Vitals(hp: 0, sp: 0, stats: stats)
        vitals.hp = vitals.hpMax
        vitals.sp = vitals.spMax
        // Default cosmetic kit uses the appearance-chosen hair style. The rest
        // of the slots get the basic starter outfit (tunic, long-pants, etc.).
        var cosmetic = carriedCosmetic.isEmpty ? Self.defaultCosmetic : carriedCosmetic
        cosmetic["hair"] = appearance.hairStyle
        return TokegotchiState(
            identity: Identity(
                name: name,
                generation: generation,
                bornAt: bornAt,
                ageTokens: 0,
                lifespanTokens: 500_000,
                appearance: appearance
            ),
            vitals: vitals,
            progress: Progress(exp: 0, gold: 0),
            world: World(currentRegion: nil, reputation: carriedReputation),
            inventory: Inventory(
                items: carriedItems,
                equippedCosmetic: cosmetic,
                equippedGear: [:],
                skillsLearned: [],
                activeQuests: []
            ),
            bloodline: Bloodline(ancestors: ancestors)
        )
    }

    static let defaultCosmetic: [String: String?] = [
        "hair":    "horns",
        "shirt":   "tunic",
        "pants":   "long-pants",
        "belt":    "leather",
        "hat":     nil,
        "eyewear": nil,
        "cape":    nil,
    ]
}

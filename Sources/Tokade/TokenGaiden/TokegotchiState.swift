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
    /// Cumulative quest counters. Optional so saves written before this field
    /// existed still decode; persisted in the save so quest progress survives
    /// app restarts (issue #30). Mutate via `questTelemetryOrEmpty`.
    var questTelemetry: QuestTelemetry?

    /// Non-optional accessor: reads as empty telemetry when unset and
    /// materializes it on write.
    var questTelemetryOrEmpty: QuestTelemetry {
        get { questTelemetry ?? QuestTelemetry() }
        set { questTelemetry = newValue }
    }

    struct Identity: Codable, Equatable {
        var name: String
        var generation: Int
        var bornAt: Date
        /// Accumulated weighted token count. The lifespan threshold is
        /// stored separately so quest-derived extensions can grow it.
        var ageTokens: Int
        var lifespanTokens: Int
        /// Most recently sampled `fiveHour.usedPercentage` from the rate
        /// limits, used to compute Δ% per tick so aging + HP drain are
        /// driven by plan-budget consumption rather than raw token counts.
        /// Optional for save-file compatibility — nil means "first tick."
        var lastUsedPercentage: Double?
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

    struct Stats: Codable, Equatable, Hashable {
        var str: Int
        var dex: Int
        var int: Int
        var agi: Int
        var cha: Int

        /// New Tokegotchis hatch with random low-roll stats so every first-gen
        /// pet has a distinct starting personality. Subsequent generations
        /// inherit 30% of peak instead.
        static func randomStarter() -> Stats {
            Stats(
                str: Int.random(in: 3...10),
                dex: Int.random(in: 3...10),
                int: Int.random(in: 3...10),
                agi: Int.random(in: 3...10),
                cha: Int.random(in: 3...10)
            )
        }

        /// Deterministic fallback for tests + the rare case we need a known
        /// starting stat baseline. Sum = 25; same as the expected mean of
        /// `randomStarter()`.
        static let starter = Stats(str: 5, dex: 5, int: 5, agi: 5, cha: 5)
    }

    struct Progress: Codable, Equatable {
        var exp: Int
        var gold: Int
    }

    struct World: Codable, Equatable {
        var currentRegion: String?            // cwd-prefix identifying current region
        var reputation: [String: Int]         // region → 0–100
        var flavors: [String: Region.Flavor]? // region → seeded flavor (nil for legacy saves)
        /// Running per-region count of consumed events; reputation ticks +1
        /// per 50 events in a region (capped at 100). Optional for save-file
        /// compatibility with the M0 schema.
        var eventCounts: [String: Int]?
        /// Per-region event-count threshold for the next encounter. Re-rolled
        /// (10–20 range) every time an encounter fires so cadence has jitter.
        var nextEncounterAt: [String: Int]?
        /// Per-region accumulated "steps" — LoC + tool calls + tokens/200.
        /// Discovery thresholds key off this rather than raw event count.
        /// Optional for save-file compatibility with the M0 schema.
        var regionSteps: [String: Int]?
        /// Player-pinned region for fast-travel. When set, telemetry from
        /// other sessions still ticks the pet but the town card stays here.
        var pinnedRegion: String?
        /// Last observed event time per region; the map highlights regions
        /// active in the last minute.
        var lastActiveAt: [String: Date]?
        /// Stable 2D map positions per region (normalized [0, 1]). Frozen
        /// on first discovery so the layout doesn't shuffle.
        var regionPositions: [String: [Double]]?
        /// Real-time timestamp of the last encounter trigger across any
        /// region. Used to rate-cap encounter spawns so heavy-plan users
        /// don't get drowned in fights. Optional for save-file compatibility.
        var lastEncounterAt: Date?
    }

    struct Inventory: Codable, Equatable {
        var items: [String: Int]              // itemId → count
        var equippedCosmetic: [String: String?]
        var equippedGear: [String: String?]
        var skillsLearned: [String]
        var activeQuests: [String]
        /// Progress toward the next stat-item drop, keyed by tool. Drops fire
        /// when the counter reaches `toolDropThreshold` then reset. Optional
        /// for save-file compatibility with earlier schemas.
        var toolProgress: [String: Int]?
        /// Quest IDs the player has finished and claimed. Locked from
        /// re-acceptance so trivially-reached quests (e.g., "reach CHA 8"
        /// when CHA is already 8) can't be looped.
        var completedQuestIds: [String]?
        /// Cosmetic IDs the player has unlocked. Cosmetics not in this set
        /// appear in the Wardrobe as silhouettes with their unlock hint
        /// (e.g., "Earned from First Blood"). Carries through bloodline so
        /// a death doesn't strip the collection. Optional for save-file
        /// compatibility — nil is treated as "starter set only".
        var discoveredCosmetics: [String]?
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

    /// Set once when the pet dies. Ticks no longer mutate state while this is
    /// non-nil — the alive layout is replaced by the eulogy + "hatch next"
    /// screen until the player starts a new generation.
    var deathState: PendingDeath?

    struct PendingDeath: Codable, Equatable {
        let cause: CauseOfDeath
        let diedAt: Date
        let peakStats: Stats
        let daysLived: Int
    }

    /// Wall-clock instant the pet went down (HP=0). nil when HP > 0. The pet
    /// dies of `.hpZero` once `criticalGraceSeconds` elapse from this stamp.
    /// Driven by `TickProcessor.advanceCriticalClock` every tick — including
    /// idle ticks — so death/recovery don't depend on active Claude usage
    /// (issue #37). Optional for save-file compatibility; pre-#37 saves used a
    /// `criticalTicks` counter, which is simply ignored on decode.
    var criticalSince: Date?

    /// Wall-clock seconds a pet survives at HP=0 before dying. ~150s (the old
    /// 50 ticks × 3s cadence) — long enough to feed it within a session, short
    /// enough that the Critical warning means something.
    static let criticalGraceSeconds: TimeInterval = 150

    /// In-progress active-combat battle, if any. nil when there's no
    /// encounter awaiting player input. Optional for save-file compatibility
    /// with the M0 schema.
    var activeBattle: ActiveBattle?

    /// Whether the pet's age has reached its lifespan.
    var isAgedOut: Bool {
        identity.ageTokens >= identity.lifespanTokens
    }

    /// Whether the pet has hit HP=0 (enters Critical state).
    var isCritical: Bool {
        vitals.hp <= 0 && deathState == nil
    }

    /// Whether the pet is dead (alive layout should be replaced).
    var isDead: Bool { deathState != nil }

    /// Days lived since birth (rounded down).
    var daysLived: Int {
        let elapsed = (deathState?.diedAt ?? Date()).timeIntervalSince(identity.bornAt)
        return max(0, Int(elapsed / 86400))
    }
}

extension TokegotchiState {
    /// Build a new starter pet from a chosen appearance + name. Called once
    /// at character creation or on the first launch after a permanent death.
    /// Seeded starter inventory for first-generation Tokegotchis. Gives the
    /// player enough food to last the first few sessions before drops catch
    /// up. Subsequent generations carry their own inheritance.
    static let starterItems: [String: Int] = [
        "bread":           3,
        "small-sp-potion": 1,
    ]

    /// Starter gold a first-gen Tokegotchi spawns with. Enough to buy a few
    /// items at the first merchant before encounters start dropping any.
    static let starterGold = 50

    static func newStarter(
        name: String,
        appearance: Appearance,
        generation: Int = 1,
        bornAt: Date = Date(),
        inheritedStats: Stats? = nil,
        ancestors: [Ancestor] = [],
        carriedItems: [String: Int]? = nil,
        carriedCosmetic: [String: String?] = [:],
        carriedReputation: [String: Int] = [:]
    ) -> TokegotchiState {
        // First-gen pets get random low-roll stats; inheriting generations use
        // their inherited 30%-of-peak slate from hatchNextGeneration.
        let stats = inheritedStats ?? Stats.randomStarter()
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
                lifespanTokens: 180_000_000,
                lastUsedPercentage: nil,
                appearance: appearance
            ),
            vitals: vitals,
            progress: Progress(exp: 0, gold: Self.starterGold),
            world: World(
                currentRegion: nil,
                reputation: carriedReputation,
                flavors: [:],
                eventCounts: [:]
            ),
            inventory: Inventory(
                items: carriedItems ?? Self.starterItems,
                equippedCosmetic: cosmetic,
                equippedGear: [:],
                skillsLearned: [],
                activeQuests: [],
                toolProgress: [:],
                completedQuestIds: nil,
                // New pet starts with every "starter" cosmetic already known
                // so the wardrobe carousel has the baseline kit. Earned
                // cosmetics from the previous generation persist via
                // hatchNextGeneration (carriedDiscovered).
                discoveredCosmetics: CosmeticCatalog.starters.map(\.id)
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
        "held":    nil,
    ]
}

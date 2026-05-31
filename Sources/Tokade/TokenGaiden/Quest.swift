import Foundation

/// A quest definition. NPCs offer these; once accepted, the engine tracks
/// progress from telemetry and marks them complete when the objective is met.
struct Quest: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let objective: Objective
    let rewardGold: Int
    let rewardExp: Int
    let rewardItem: String?

    enum Objective: Hashable {
        /// Consume N matching tool calls (e.g., N Bash invocations).
        case toolCalls(tool: String, count: Int)
        /// Reach the given stat threshold.
        case reachStat(stat: String, value: Int)
        /// Earn cumulative gold.
        case earnGold(amount: Int)
        /// Defeat N monsters of any type in encounters.
        case defeatMonsters(count: Int)
        /// Reach reputation N in any region.
        case reachReputation(amount: Int)
    }
}

/// Persisted progress on a quest the player has accepted. Lives inside the
/// Tokegotchi save under `inventory.activeQuests`.
struct QuestProgress: Codable, Hashable {
    let questId: String
    let acceptedAt: Date
    var progress: Int
    var completed: Bool
}

enum QuestCatalog {
    /// Quests offered by region flavor. v1: each region has 2 quests
    /// achievable by mid-game stats and a normal session of Claude usage.
    static func quests(for flavor: Region.Flavor) -> [Quest] {
        switch flavor {
        case .stonework:
            return [
                Quest(id: "stone-strong-arms",
                      name: "Strong Arms",
                      description: "Show the quarry what you can lift. Reach STR 8.",
                      objective: .reachStat(stat: "STR", value: 8),
                      rewardGold: 40, rewardExp: 30, rewardItem: "hearty-meat"),
                Quest(id: "stone-50-bash",
                      name: "Break Some Rocks",
                      description: "Use Bash 50 times.",
                      objective: .toolCalls(tool: "Bash", count: 50),
                      rewardGold: 30, rewardExp: 20, rewardItem: nil),
            ]
        case .ironFortress:
            return [
                Quest(id: "iron-monster-cull",
                      name: "Compile Beetle Cull",
                      description: "Defeat 5 monsters anywhere.",
                      objective: .defeatMonsters(count: 5),
                      rewardGold: 60, rewardExp: 40, rewardItem: "medium-sp-potion"),
                Quest(id: "iron-100-edits",
                      name: "Steady Hand",
                      description: "Make 100 file edits with the chisel.",
                      objective: .toolCalls(tool: "Edit", count: 100),
                      rewardGold: 50, rewardExp: 30, rewardItem: nil),
            ]
        case .gardenVillage:
            return [
                Quest(id: "garden-research",
                      name: "Deep Research",
                      description: "Look things up with WebFetch 20 times.",
                      objective: .toolCalls(tool: "WebFetch", count: 20),
                      rewardGold: 35, rewardExp: 25, rewardItem: "small-sp-potion"),
                Quest(id: "garden-wise",
                      name: "Sage of the Garden",
                      description: "Reach INT 8.",
                      objective: .reachStat(stat: "INT", value: 8),
                      rewardGold: 40, rewardExp: 30, rewardItem: nil),
            ]
        case .bazaar:
            return [
                Quest(id: "bazaar-coffers",
                      name: "Fill the Coffers",
                      description: "Earn 200 gold total from all sources.",
                      objective: .earnGold(amount: 200),
                      rewardGold: 30, rewardExp: 25, rewardItem: "hearty-meat"),
                Quest(id: "bazaar-charmed",
                      name: "Charmed Life",
                      description: "Reach CHA 8.",
                      objective: .reachStat(stat: "CHA", value: 8),
                      rewardGold: 40, rewardExp: 30, rewardItem: nil),
            ]
        case .openSteppe:
            return [
                Quest(id: "steppe-fast",
                      name: "Run with the Wind",
                      description: "Reach AGI 8.",
                      objective: .reachStat(stat: "AGI", value: 8),
                      rewardGold: 40, rewardExp: 30, rewardItem: nil),
                Quest(id: "steppe-explore",
                      name: "Wanderer's Way",
                      description: "Visit at least 3 distinct regions (build reputation).",
                      objective: .reachReputation(amount: 1),
                      rewardGold: 25, rewardExp: 15, rewardItem: nil),
            ]
        case .wilderness:
            return [
                Quest(id: "wild-survive",
                      name: "Survive the Wilds",
                      description: "Defeat 3 monsters here.",
                      objective: .defeatMonsters(count: 3),
                      rewardGold: 25, rewardExp: 20, rewardItem: "bread"),
            ]
        }
    }

    static func byId(_ id: String) -> Quest? {
        for flavor in Region.Flavor.allCases {
            if let q = quests(for: flavor).first(where: { $0.id == id }) { return q }
        }
        return nil
    }
}

/// Pure-functional quest engine. Acceptance, progress tracking, completion.
enum QuestEngine {
    enum AcceptResult: Equatable {
        case accepted, alreadyAccepted, alreadyCompleted, alreadyClaimed
    }

    enum ClaimResult: Equatable {
        case claimed(gold: Int, exp: Int, item: String?)
        case notComplete
        case unknown
    }

    /// Add the quest to active quests if not already there. Quests the
    /// player has previously claimed are locked from re-acceptance — prevents
    /// infinite-claim loops on trivially-satisfied conditions.
    static func accept(_ quest: Quest, state: TokegotchiState) -> (TokegotchiState, AcceptResult) {
        if (state.inventory.completedQuestIds ?? []).contains(quest.id) {
            return (state, .alreadyClaimed)
        }
        if let existing = active(state: state).first(where: { $0.questId == quest.id }) {
            return (state, existing.completed ? .alreadyCompleted : .alreadyAccepted)
        }
        var s = state
        var entries = active(state: s)
        entries.append(QuestProgress(questId: quest.id, acceptedAt: Date(), progress: 0, completed: false))
        s.inventory.activeQuests = encode(entries)
        return (s, .accepted)
    }

    /// Claim a completed quest. Pays the reward, removes from active.
    static func claim(_ quest: Quest, state: TokegotchiState) -> (TokegotchiState, ClaimResult) {
        var entries = active(state: state)
        guard let idx = entries.firstIndex(where: { $0.questId == quest.id }) else {
            return (state, .unknown)
        }
        guard entries[idx].completed else { return (state, .notComplete) }
        var s = state
        s.progress.gold += quest.rewardGold
        s.progress.exp += quest.rewardExp
        if let item = quest.rewardItem {
            s.inventory.items[item, default: 0] += 1
        }
        entries.remove(at: idx)
        s.inventory.activeQuests = encode(entries)
        // Mark as permanently claimed so it can't be re-accepted.
        var claimed = s.inventory.completedQuestIds ?? []
        if !claimed.contains(quest.id) { claimed.append(quest.id) }
        s.inventory.completedQuestIds = claimed
        return (s, .claimed(gold: quest.rewardGold, exp: quest.rewardExp, item: quest.rewardItem))
    }

    /// Re-evaluate all active quests against the current state and update
    /// `progress` / `completed`. Pure-functional.
    static func evaluate(state: TokegotchiState, telemetry: QuestTelemetry) -> TokegotchiState {
        var entries = active(state: state)
        for i in entries.indices {
            guard !entries[i].completed,
                  let quest = QuestCatalog.byId(entries[i].questId) else { continue }
            let (progress, done) = evaluateObjective(quest.objective, state: state, telemetry: telemetry)
            entries[i].progress = progress
            entries[i].completed = done
        }
        var s = state
        s.inventory.activeQuests = encode(entries)
        return s
    }

    /// Decoded list of active quests (the persisted form is a `[String]` for
    /// schema compatibility; we encode QuestProgress as JSON inside each
    /// string).
    static func active(state: TokegotchiState) -> [QuestProgress] {
        state.inventory.activeQuests.compactMap { decode($0) }
    }

    // MARK: - Internals

    private static func encode(_ entries: [QuestProgress]) -> [String] {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return entries.compactMap { entry in
            guard let data = try? enc.encode(entry), let s = String(data: data, encoding: .utf8) else { return nil }
            return s
        }
    }

    private static func decode(_ s: String) -> QuestProgress? {
        guard let data = s.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(QuestProgress.self, from: data)
    }

    private static func evaluateObjective(
        _ obj: Quest.Objective,
        state: TokegotchiState,
        telemetry: QuestTelemetry
    ) -> (progress: Int, done: Bool) {
        switch obj {
        case let .toolCalls(tool, count):
            let p = telemetry.toolCounts[tool] ?? 0
            return (min(p, count), p >= count)
        case let .reachStat(stat, value):
            let s = state.vitals.stats
            let v: Int = {
                switch stat {
                case "STR": return s.str
                case "DEX": return s.dex
                case "INT": return s.int
                case "AGI": return s.agi
                case "CHA": return s.cha
                default:    return 0
                }
            }()
            return (min(v, value), v >= value)
        case let .earnGold(amount):
            let v = telemetry.cumulativeGold
            return (min(v, amount), v >= amount)
        case let .defeatMonsters(count):
            let v = telemetry.monstersDefeated
            return (min(v, count), v >= count)
        case let .reachReputation(amount):
            let v = state.world.reputation.values.max() ?? 0
            return (min(v, amount), v >= amount)
        }
    }
}

/// Telemetry shared with the quest engine. Tracks cumulative counters the
/// game state doesn't already store.
struct QuestTelemetry: Codable, Equatable {
    var toolCounts: [String: Int] = [:]
    var cumulativeGold: Int = 0
    var monstersDefeated: Int = 0
}


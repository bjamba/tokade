import Foundation

/// One observable change resulting from a Claude Code event being processed
/// against the Tokegotchi state. UI surfaces these as toasts / animations.
enum TickResult: Equatable {
    case itemDropped(itemId: String, count: Int)
    case hpChanged(delta: Int)
    case spChanged(delta: Int)
    case ageAdvanced(byPoints: Int, fromModel: String)
    case statBoost(stat: String, delta: Int)
    case enteredCritical
    case died(cause: TokegotchiState.CauseOfDeath)
    case encounter(monsterName: String, outcome: EncounterEngine.Outcome)
    case achievementEarned(id: String)
}

/// Translates UsageEvents into game effects. Pure-functional: takes the event +
/// previous state, returns the new state plus a list of `TickResult`s.
///
/// This is layer 1 of Token Gaiden — the tick economy from
/// `docs/02-design/TOKADE_TAB.md`. Tool calls drop themed stat items, edits
/// drop food, slash commands drop SP potions, tokens consumed drain HP and
/// advance age (model-weighted).
enum TickProcessor {
    // MARK: - Public

    /// Process one usage event against the current state. Returns the updated
    /// state and the list of observable effects.
    ///
    /// `previouslyAccountedTotal` is the cumulative `grandTotal` we've already
    /// processed for the relevant message — needed so we don't double-count
    /// tokens if the event is re-emitted as the JSONL grows.
    static func process(
        _ event: UsageEvent,
        state: TokegotchiState,
        deltaTokens: Int
    ) -> (TokegotchiState, [TickResult]) {
        var s = state
        var results: [TickResult] = []
        guard deltaTokens > 0 else { return (s, results) }

        // ---- HP drain ----
        let hpCost = hpDrain(model: event.model, tokens: deltaTokens)
        if hpCost > 0 {
            s.vitals.hp -= hpCost
            results.append(.hpChanged(delta: -hpCost))
        }

        // ---- Age advance ----
        let agePoints = ageAdvance(model: event.model, tokens: deltaTokens)
        if agePoints > 0 {
            s.identity.ageTokens += agePoints
            results.append(.ageAdvanced(byPoints: agePoints, fromModel: event.model))
        }

        // ---- Tool calls → stat items + food on edit-like calls ----
        for tool in event.tools {
            let drop = toolDrop(tool: tool)
            s.inventory.items[drop.itemId, default: 0] += drop.count
            results.append(.itemDropped(itemId: drop.itemId, count: drop.count))
            // Edit-flavored tools also drop bread (we don't have an LoC-delta
            // signal yet, so every Edit/Write is a small bread).
            if tool == "Edit" || tool == "Write" || tool == "NotebookEdit" {
                s.inventory.items["bread", default: 0] += 1
                results.append(.itemDropped(itemId: "bread", count: 1))
            }
        }

        // ---- Slash command → SP potion ----
        if event.slashCommand != nil {
            let potion = "small-sp-potion"
            s.inventory.items[potion, default: 0] += 1
            results.append(.itemDropped(itemId: potion, count: 1))
        }

        // ---- Region tracking ----
        if let cwd = event.cwd {
            let region = Region.identifier(for: cwd)
            s.world.currentRegion = region

            // Seed flavor on first visit (cheap; only does filesystem reads
            // when the key isn't already present).
            if s.world.flavors == nil { s.world.flavors = [:] }
            if s.world.flavors?[region] == nil {
                s.world.flavors?[region] = Region.flavor(for: cwd)
            }

            // Event counter; every 50 events grants +1 reputation (cap 100).
            if s.world.eventCounts == nil { s.world.eventCounts = [:] }
            s.world.eventCounts?[region, default: 0] += 1
            let count = s.world.eventCounts?[region] ?? 0
            let earnedRep = min(100, count / 50)
            let priorRep = s.world.reputation[region, default: 0]
            if earnedRep > priorRep {
                s.world.reputation[region] = earnedRep
            }
        }

        // ---- Encounter trigger (every 25 events in the same region) ----
        if let region = s.world.currentRegion {
            let count = s.world.eventCounts?[region] ?? 0
            if count > 0, count % 25 == 0 {
                let flavor = s.world.flavors?[region] ?? .wilderness
                if let monster = EncounterEngine.choose(
                    for: flavor, playerStats: s.vitals.stats, salt: count / 25
                ) {
                    let (afterFight, outcome) = EncounterEngine.resolve(monster, against: s)
                    s = afterFight
                    results.append(.encounter(monsterName: monster.monsterName, outcome: outcome))
                }
            }
        }

        // ---- Vital clamping + death detection ----
        s.vitals.clamp()
        if s.isCritical, !state.isCritical {
            results.append(.enteredCritical)
        }
        if s.isAgedOut, !state.isAgedOut {
            results.append(.died(cause: .natural))
        }

        // ---- Achievements (check after all other effects) ----
        for newId in AchievementCatalog.newlyEarned(in: s) {
            s.inventory.items[AchievementCatalog.inventoryPrefix + newId] = 1
            results.append(.achievementEarned(id: newId))
        }

        return (s, results)
    }

    // MARK: - Internals

    /// HP drained per token, by model family. Per design doc:
    /// Haiku 1/10K, Sonnet 1/5K, Opus 1/2K.
    static func hpDrain(model: String, tokens: Int) -> Int {
        let m = model.lowercased()
        if m.contains("haiku") { return tokens / 10000 }
        if m.contains("sonnet") { return tokens / 5000 }
        if m.contains("opus") { return tokens / 2000 }
        return tokens / 8000     // default for unknown / future models
    }

    /// Age points per token, model-weighted: Haiku ×0.5, Sonnet ×1.0, Opus ×2.0.
    static func ageAdvance(model: String, tokens: Int) -> Int {
        let m = model.lowercased()
        if m.contains("haiku") { return tokens / 2 }
        if m.contains("sonnet") { return tokens }
        if m.contains("opus") { return tokens * 2 }
        return tokens
    }

    /// Map a tool name to the item it drops. User-controllable tools drop
    /// stat-themed items; low-control tools drop generic scrap.
    static func toolDrop(tool: String) -> (itemId: String, count: Int) {
        switch tool {
        case "Bash":
            return ("dumbbell", 1)
        case "Edit", "Write", "NotebookEdit":
            return ("chisel", 1)
        case "WebFetch", "WebSearch":
            return ("scroll", 1)
        case "Task":
            return ("boots", 1)
        case "Read", "Grep", "Glob", "TodoWrite":
            return ("scrap", 1)
        default:
            // MCP tools, BashOutput, KillShell, ExitPlanMode, etc.
            return ("scrap", 1)
        }
    }
}

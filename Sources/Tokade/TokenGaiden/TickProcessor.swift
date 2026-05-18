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
        deltaTokens: Int,
        combatMode: CombatMode = .passive
    ) -> (TokegotchiState, [TickResult]) {
        var s = state
        var results: [TickResult] = []
        // Once the pet is dead, no telemetry mutates it — wait for the player
        // to hatch the next generation.
        guard !s.isDead else { return (s, results) }
        guard deltaTokens > 0 else { return (s, results) }

        // Per-event token math still drives drops, encounters, and quest
        // telemetry — those scale naturally with messages, which has a
        // much narrower plan-tier spread than raw tokens.
        // HP drain and aging are now applied separately via
        // `applyBudgetWear` so they're keyed off "% of 5-hour rate-limit
        // budget consumed" instead of raw token count. That keeps wall-clock
        // lifespan + drain rate similar across Pro / Max / Max-5×.

        // ---- Tool calls → stat items (gated by threshold so drops feel earned) ----
        if s.inventory.toolProgress == nil { s.inventory.toolProgress = [:] }
        for tool in event.tools {
            let drop = toolDrop(tool: tool)
            let key = drop.itemId
            let next = (s.inventory.toolProgress?[key] ?? 0) + 1
            if next >= Self.toolDropThreshold {
                s.inventory.items[key, default: 0] += 1
                s.inventory.toolProgress?[key] = 0
                results.append(.itemDropped(itemId: key, count: 1))
            } else {
                s.inventory.toolProgress?[key] = next
            }
            // Edit-flavored tools also feed the pet on a tighter cadence.
            if tool == "Edit" || tool == "Write" || tool == "NotebookEdit" {
                let foodNext = (s.inventory.toolProgress?["bread"] ?? 0) + 1
                if foodNext >= Self.foodDropThreshold {
                    s.inventory.items["bread", default: 0] += 1
                    s.inventory.toolProgress?["bread"] = 0
                    results.append(.itemDropped(itemId: "bread", count: 1))
                } else {
                    s.inventory.toolProgress?["bread"] = foodNext
                }
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
            // Respect a player-pinned region — fast-travel overrides the
            // "follow whatever event just fired" behavior.
            if s.world.pinnedRegion == nil {
                s.world.currentRegion = region
            }

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

            // Per-region step counter for discovery thresholds.
            if s.world.regionSteps == nil { s.world.regionSteps = [:] }
            let stepsGained = Region.stepsForEvent(event)
            s.world.regionSteps?[region, default: 0] += stepsGained
            // Track recent activity per region so the map can highlight
            // sessions still firing in real time.
            if s.world.lastActiveAt == nil { s.world.lastActiveAt = [:] }
            s.world.lastActiveAt?[region] = Date()
            // Assign a stable map position the first time we see a region.
            if s.world.regionPositions == nil { s.world.regionPositions = [:] }
            if s.world.regionPositions?[region] == nil {
                let p = Region.position(for: region)
                s.world.regionPositions?[region] = [p.x, p.y]
            }
        }

        // ---- Encounter trigger (every 10–20 events in the same region) ----
        // Skipped if an active battle is already in progress (player owes it
        // input). Combat mode is set by the caller; passive resolves here,
        // active stages an ActiveBattle for the UI to consume.
        // Also rate-capped to one encounter per `encounterCooldown` of real
        // time, regardless of how many events have piled up — keeps heavy-
        // plan users from being drowned in fights.
        if s.activeBattle == nil, let region = s.world.currentRegion {
            let count = s.world.eventCounts?[region] ?? 0
            if s.world.nextEncounterAt == nil { s.world.nextEncounterAt = [:] }
            let target = s.world.nextEncounterAt?[region] ?? Int.random(in: 10...20)
            s.world.nextEncounterAt?[region] = target
            let now = Date()
            let cooldownOK = (s.world.lastEncounterAt
                .map { now.timeIntervalSince($0) >= Self.encounterCooldown }) ?? true
            if count >= target && cooldownOK {
                let flavor = s.world.flavors?[region] ?? .wilderness
                if let monster = EncounterEngine.choose(
                    for: flavor, playerStats: s.vitals.stats, salt: count
                ) {
                    // Schedule next encounter trigger with fresh jitter.
                    s.world.nextEncounterAt?[region] = count + Int.random(in: 10...20)
                    s.world.lastEncounterAt = now
                    if combatMode == .active {
                        s.activeBattle = ActiveBattle(encounter: monster)
                        results.append(.encounter(monsterName: monster.monsterName, outcome: .victory(expGained: 0, goldGained: 0)))
                    } else {
                        let (afterFight, outcome) = EncounterEngine.resolve(monster, against: s)
                        s = afterFight
                        results.append(.encounter(monsterName: monster.monsterName, outcome: outcome))
                    }
                }
            }
        }

        // ---- Vital clamping + death detection ----
        s.vitals.clamp()

        // Critical state machine. HP=0 starts a grace counter; recovery
        // (HP > 0) resets it; running out of grace kills the pet.
        if s.vitals.hp <= 0 {
            if s.criticalTicks == nil {
                s.criticalTicks = 0
                results.append(.enteredCritical)
            } else {
                s.criticalTicks = (s.criticalTicks ?? 0) + 1
            }
            if (s.criticalTicks ?? 0) >= TokegotchiState.criticalGraceTicks {
                s.deathState = TokegotchiState.PendingDeath(
                    cause: .hpZero,
                    diedAt: Date(),
                    peakStats: s.vitals.stats,
                    daysLived: s.daysLived
                )
                results.append(.died(cause: .hpZero))
            }
        } else {
            s.criticalTicks = nil
        }

        // Natural death wins over critical: aged-out always triggers, even
        // if HP > 0. Acts as the hard ceiling past which survival is impossible.
        if s.isAgedOut, s.deathState == nil {
            s.deathState = TokegotchiState.PendingDeath(
                cause: .natural,
                diedAt: Date(),
                peakStats: s.vitals.stats,
                daysLived: s.daysLived
            )
            results.append(.died(cause: .natural))
        }

        // ---- Achievements (check after all other effects) ----
        for newId in AchievementCatalog.newlyEarned(in: s) {
            s.inventory.items[AchievementCatalog.inventoryPrefix + newId] = 1
            results.append(.achievementEarned(id: newId))
        }

        return (s, results)
    }

    // MARK: - Budget-based wear (plan-normalized)

    /// HP drained at 100% consumption of the 5-hour rate-limit window.
    /// Sized so a heavy-burn user takes ~half their hpMax (≈100 HP) per
    /// rate-limit window — enough to require feeding, not enough to kill.
    /// Plan-normalized: same %-of-window = same drain for Pro / Max / Max-5×.
    static let hpDrainPerFullWindow: Double = 60

    /// Age points credited at 100% consumption of the 5-hour rate-limit
    /// window. Sized so a continuously rate-limited user (the heaviest
    /// realistic case) ages roughly the full lifespan in ~7-10 real days,
    /// while moderate users stretch to weeks. 180M / 21K ≈ 8500 windows;
    /// at one window per 5h = ~ a quarter-million wall-clock hours of light
    /// usage, but heavy continuous usage burns through faster.
    static let ageTokensPerFullWindow: Double = 1_500_000

    /// Apply plan-budget-driven HP drain + aging since the last sampled
    /// percentage. Returns the updated state and any results (hp change,
    /// age advance, critical/death) the UI should surface. Called once
    /// per tick batch from the store.
    ///
    /// - Parameter usedPercentage: current 5-hour `fiveHour.usedPercentage`
    ///   from the live rate-limit snapshot. nil → no rate-limit data this
    ///   tick; we skip wear and update nothing.
    static func applyBudgetWear(
        state: TokegotchiState,
        usedPercentage: Double?
    ) -> (TokegotchiState, [TickResult]) {
        var s = state
        var results: [TickResult] = []
        guard !s.isDead else { return (s, results) }
        guard let pct = usedPercentage else { return (s, results) }
        // First observation: record baseline only, no wear applied. This
        // means a fresh-launched app doesn't suddenly age the pet by the
        // historical % that's already on the clock.
        guard let prior = s.identity.lastUsedPercentage else {
            s.identity.lastUsedPercentage = pct
            return (s, results)
        }
        // Rate-limit windows roll. When pct drops (window rollover) we
        // treat it as "no consumption this tick" — only positive deltas
        // age the pet.
        let delta = max(0, pct - prior)
        s.identity.lastUsedPercentage = pct
        guard delta > 0 else { return (s, results) }
        // pct is on 0..100 scale; convert to fraction.
        let fraction = delta / 100.0
        let hpCost = Int((fraction * hpDrainPerFullWindow).rounded())
        if hpCost > 0 {
            s.vitals.hp = max(0, s.vitals.hp - hpCost)
            results.append(.hpChanged(delta: -hpCost))
        }
        let agePoints = Int((fraction * ageTokensPerFullWindow).rounded())
        if agePoints > 0 {
            s.identity.ageTokens += agePoints
            // Use "plan" as the model tag so the UI surfaces a generic
            // origin rather than a stale model name.
            results.append(.ageAdvanced(byPoints: agePoints, fromModel: "plan"))
        }
        // Probabilistic natural death past the 60% "elder" threshold. The
        // hazard rate scales as danger² where danger = (ageRatio - 0.6)/0.4,
        // integrated so the cumulative hazard across the 60→100% band ≈ 1.0
        // — most pets die in the elder band, some hang on to 100%.
        if s.deathState == nil, agePoints > 0 {
            let lifespan = Double(max(s.identity.lifespanTokens, 1))
            let ageRatio = Double(s.identity.ageTokens) / lifespan
            if ageRatio > 0.60 && ageRatio < 1.0 {
                let danger = min(1.0, (ageRatio - 0.60) / 0.40)
                let perPointRate = 3.0 * danger * danger / (lifespan * 0.40)
                let dieChance = 1.0 - pow(1.0 - perPointRate, Double(agePoints))
                if Double.random(in: 0..<1) < dieChance {
                    s.deathState = TokegotchiState.PendingDeath(
                        cause: .natural,
                        diedAt: Date(),
                        peakStats: s.vitals.stats,
                        daysLived: s.daysLived
                    )
                    results.append(.died(cause: .natural))
                }
            }
        }
        return (s, results)
    }

    // MARK: - Internals

    /// Minimum wall-clock seconds between encounter triggers across all
    /// regions. Prevents heavy-plan users from being drowned in fights
    /// when their event count piles up rapidly. 90s is the same cadence a
    /// moderate user naturally hits, so light users feel no change.
    static let encounterCooldown: TimeInterval = 90

    /// Tool calls needed to drop one themed item. Higher = slower drops.
    /// Tuned for a couple drops per hour at typical Claude usage, not per
    /// minute.
    static let toolDropThreshold = 30
    /// Edit-flavored calls needed for one bread. Lower than tool threshold
    /// because bread is the primary HP-recovery item.
    static let foodDropThreshold = 20

    /// HP drained per token, by model family. Calibrated so a moderate day
    /// of usage drains a noticeable chunk of HP — enough that the player
    /// needs to feed the pet regularly, but not so much that one prompt
    /// kills it.
    static func hpDrain(model: String, tokens: Int) -> Int {
        let m = model.lowercased()
        if m.contains("haiku") { return tokens / 200_000 }
        if m.contains("sonnet") { return tokens / 100_000 }
        if m.contains("opus") { return tokens / 40_000 }
        return tokens / 160_000     // default for unknown / future models
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

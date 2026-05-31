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
/// drop food, slash commands drop SP potions; HP drain and aging are keyed off
/// % of the 5-hour budget window (plan-normalized) and then weighted by the
/// model mix consumed — Haiku gentler, Opus harsher (see `applyBudgetWear`).
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
            if count >= target, cooldownOK {
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

        // The HP=0 critical/death machine is NOT handled here — it's driven by
        // wall-clock time in `advanceCriticalClock`, called every store tick
        // (even when no Claude usage arrives) so a downed pet still dies or
        // recovers while you're idle (issue #37).

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
    /// Fraction of the model multiplier that applies to HP drain. Aging takes
    /// the full multiplier (longevity is the headline model signal); HP takes
    /// half-strength so an Opus-heavy window is demanding but not instantly
    /// lethal, preserving the "enough to require feeding, not enough to kill"
    /// guarantee for the neutral case.
    static let hpModelWeightStrength: Double = 0.5

    static func applyBudgetWear(
        state: TokegotchiState,
        usedPercentage: Double?,
        modelMix: ModelMix = .neutral
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
        // HP takes a softened model weighting; aging takes the full weighting.
        let hpMultiplier = 1.0 + (modelMix.multiplier - 1.0) * hpModelWeightStrength
        let hpCost = Int((fraction * hpDrainPerFullWindow * hpMultiplier).rounded())
        if hpCost > 0 {
            s.vitals.hp = max(0, s.vitals.hp - hpCost)
            results.append(.hpChanged(delta: -hpCost))
        }
        let agePoints = Int((fraction * ageTokensPerFullWindow * modelMix.multiplier).rounded())
        if agePoints > 0 {
            s.identity.ageTokens += agePoints
            // Tag the toast with the dominant model family so the player sees
            // *why* the pet aged the way it did (Opus ages faster than Haiku).
            results.append(.ageAdvanced(byPoints: agePoints, fromModel: modelMix.label))
        }
        // Probabilistic natural death past the 60% "elder" threshold. The
        // hazard rate scales as danger² where danger = (ageRatio - 0.6)/0.4,
        // integrated so the cumulative hazard across the 60→100% band ≈ 1.0
        // — most pets die in the elder band, some hang on to 100%.
        if s.deathState == nil, agePoints > 0 {
            let lifespan = Double(max(s.identity.lifespanTokens, 1))
            let ageRatio = Double(s.identity.ageTokens) / lifespan
            if ageRatio > 0.60, ageRatio < 1.0 {
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

    /// Advance the HP=0 critical/death clock against wall-clock time. Called
    /// once per store tick — including idle ticks with no Claude usage — so a
    /// downed pet still dies after the grace period, and a fed pet still
    /// recovers, even when you're not actively burning tokens (issue #37).
    ///
    /// - When HP ≤ 0 and not already counting: stamp `criticalSince` (enters
    ///   Critical).
    /// - When HP ≤ 0 and `criticalGraceSeconds` have elapsed since that stamp:
    ///   the pet dies of `.hpZero`.
    /// - When HP > 0: clear the stamp (recovered).
    ///
    /// `now` is injectable so tests don't depend on real time.
    static func advanceCriticalClock(
        state: TokegotchiState,
        now: Date = Date()
    ) -> (TokegotchiState, [TickResult]) {
        var s = state
        var results: [TickResult] = []
        guard !s.isDead else { return (s, results) }

        if s.vitals.hp <= 0 {
            if let since = s.criticalSince {
                if now.timeIntervalSince(since) >= TokegotchiState.criticalGraceSeconds {
                    s.deathState = TokegotchiState.PendingDeath(
                        cause: .hpZero,
                        diedAt: now,
                        peakStats: s.vitals.stats,
                        daysLived: s.daysLived
                    )
                    results.append(.died(cause: .hpZero))
                }
            } else {
                s.criticalSince = now
                results.append(.enteredCritical)
            }
        } else {
            s.criticalSince = nil
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

    /// Per-model wear severity, Sonnet-centered at 1.0 so the existing
    /// plan-normalized calibration is unchanged for a Sonnet user. Haiku is
    /// gentler, Opus harsher — this is what turns "which model you run" into a
    /// survival/longevity signal (issue #36).
    static func modelSeverity(model: String) -> Double {
        let m = model.lowercased()
        if m.contains("haiku") { return 0.5 }
        if m.contains("sonnet") { return 1.0 }
        if m.contains("opus") { return 2.0 }
        return 1.0  // unknown / future models stay neutral
    }

    /// Friendly family label for the wear toast.
    static func modelFamily(_ model: String) -> String {
        let m = model.lowercased()
        if m.contains("haiku") { return "Haiku" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("opus") { return "Opus" }
        return "plan"
    }

    /// The model character of a tick batch: a token-weighted severity
    /// multiplier plus a label naming the dominant family (or "mixed").
    struct ModelMix: Equatable {
        /// Token-weighted mean of `modelSeverity` across the batch. 1.0 when
        /// there are no billable tokens, so wear is unchanged.
        let multiplier: Double
        /// Dominant model family (> 60% of tokens), else "mixed", else "plan".
        let label: String

        static let neutral = ModelMix(multiplier: 1.0, label: "plan")
    }

    /// Derive the `ModelMix` from the events processed this tick. Weighted by
    /// each event's `grandTotal` so a few huge Opus turns outweigh many tiny
    /// Haiku ones.
    static func modelMix(for events: [UsageEvent]) -> ModelMix {
        var totalTokens = 0
        var weighted = 0.0
        var byFamily: [String: Int] = [:]
        for e in events {
            let tok = e.grandTotal
            guard tok > 0 else { continue }
            weighted += Double(tok) * modelSeverity(model: e.model)
            totalTokens += tok
            byFamily[modelFamily(e.model), default: 0] += tok
        }
        guard totalTokens > 0 else { return .neutral }
        let multiplier = weighted / Double(totalTokens)
        let label: String = {
            if let top = byFamily.max(by: { $0.value < $1.value }),
               Double(top.value) / Double(totalTokens) > 0.6 {
                return top.key
            }
            return "mixed"
        }()
        return ModelMix(multiplier: multiplier, label: label)
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

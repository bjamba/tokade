import Foundation
import Observation
import os.log

/// Owns the live Tokegotchi state and the index of which UsageEvents we've
/// already accounted for. Bridges `UsageStore` (telemetry) into Token Gaiden
/// (game effects). Sibling of `UsageStore` — both held by `TokadeApp`.
@MainActor
@Observable
final class TokenGaidenStore {
    private(set) var state: TokegotchiState?
    private(set) var lastResults: [TickResult] = []
    /// Stable identity for each event we've consumed, so we don't double-count
    /// when the JSONL is re-read. Keyed by `(messageId ?? "", timestamp)`.
    private var accountedTokens: [String: Int] = [:]

    private let save = TokegotchiSave()
    private let log = Logger(subsystem: "com.bjamba.tokade", category: "TokenGaiden")
    private weak var notifier: Notifier?
    /// When set, the next call to `tick(against:)` records every event's
    /// current grandTotal as already-accounted but applies no effects.
    /// Ensures a freshly hatched pet only reacts to events that arrive *after*
    /// hatching, regardless of how stale the caller's event snapshot was.
    private var pendingSeed: Bool = false

    init(notifier: Notifier? = nil) {
        self.notifier = notifier
    }

    // MARK: - Lifecycle

    /// Load the persisted state, or leave `state == nil` (caller should show
    /// the character creator in that case).
    func load() async {
        state = await save.read()
        migrateDiscoveredCosmetics()
    }

    /// Backfill `discoveredCosmetics` for pets that predate the cosmetic
    /// catalog. Adds (a) every starter and (b) anything currently equipped
    /// so the wardrobe doesn't render still-worn cosmetics as locked
    /// silhouettes. Idempotent — re-running on a populated set is a no-op.
    private func migrateDiscoveredCosmetics() {
        guard var current = state else { return }
        var owned = Set(current.inventory.discoveredCosmetics ?? [])
        let starters = CosmeticCatalog.starters.map(\.id)
        owned.formUnion(starters)
        for (_, name) in current.inventory.equippedCosmetic {
            if let n = name { owned.insert(n) }
        }
        let next = Array(owned)
        if Array(current.inventory.discoveredCosmetics ?? []).sorted() != next.sorted() {
            current.inventory.discoveredCosmetics = next
            state = current
            Task { [save] in await save.write(current) }
        }
    }

    /// Start a new bloodline. Called from the character creator on first run
    /// or after a permanent death. The next tick will seed token accounting
    /// from the live UsageStore events so the new pet ignores every token
    /// from before hatching.
    func startNewLineage(
        name: String,
        appearance: TokegotchiState.Appearance
    ) async {
        let pet = TokegotchiState.newStarter(name: name, appearance: appearance)
        state = pet
        accountedTokens.removeAll()
        pendingSeed = true
        await save.write(pet)
    }

    /// Hatch the next generation, inheriting per ADR-0005 from the dead
    /// predecessor. Called from the death screen's "Hatch next" button. Like
    /// `startNewLineage`, the next tick seeds token accounting so historical
    /// events don't retroactively charge the new pet.
    func hatchNextGeneration(
        name: String,
        appearance: TokegotchiState.Appearance
    ) async {
        guard let dead = state, let death = dead.deathState else {
            await startNewLineage(name: name, appearance: appearance)
            return
        }
        // Compose the ancestor record from the dying pet's data.
        let ancestor = TokegotchiState.Ancestor(
            name: dead.identity.name,
            generation: dead.identity.generation,
            peakStats: death.peakStats,
            ageTokensAtDeath: dead.identity.ageTokens,
            daysLived: death.daysLived,
            causeOfDeath: death.cause,
            bornAt: dead.identity.bornAt,
            diedAt: death.diedAt
        )
        var ancestors = dead.bloodline.ancestors
        ancestors.append(ancestor)

        // Inheritance: bonus on top of a fresh random-starter baseline so
        // even small progress carries forward. Bonus per stat = ceil(peak/4),
        // capped at 99 to keep numbers sane.
        let baseline = TokegotchiState.Stats.randomStarter()
        let bonus = { (peak: Int) -> Int in (peak + 3) / 4 }
        let inheritedStats = TokegotchiState.Stats(
            str: min(99, baseline.str + bonus(death.peakStats.str)),
            dex: min(99, baseline.dex + bonus(death.peakStats.dex)),
            int: min(99, baseline.int + bonus(death.peakStats.int)),
            agi: min(99, baseline.agi + bonus(death.peakStats.agi)),
            cha: min(99, baseline.cha + bonus(death.peakStats.cha))
        )
        var carriedItems = dead.inventory.items
        // Achievement entries carry through, but stat-progress counters reset.
        // (Cosmetic inventory for v1 is implicit — every cosmetic the runtime
        // bundles is available, so nothing to carry here.)
        let carriedGold = Int(Double(dead.progress.gold) * 0.1)

        var fresh = TokegotchiState.newStarter(
            name: name,
            appearance: appearance,
            generation: dead.identity.generation + 1,
            inheritedStats: inheritedStats,
            ancestors: ancestors,
            carriedItems: carriedItems,
            carriedCosmetic: dead.inventory.equippedCosmetic,
            carriedReputation: dead.world.reputation
        )
        fresh.progress.gold = carriedGold
        // Cosmetics earned during the previous life carry through to the
        // next generation — the collection is bloodline-wide.
        let priorDiscovered = dead.inventory.discoveredCosmetics ?? []
        let starters = CosmeticCatalog.starters.map(\.id)
        let merged = Array(Set(starters + priorDiscovered))
        fresh.inventory.discoveredCosmetics = merged
        state = fresh
        accountedTokens.removeAll()
        pendingSeed = true
        await save.write(fresh)
    }

    /// Erase the save file and reset in-memory state. Wired into the existing
    /// "Erase history…" flow in `MenuView`.
    func eraseHistory() async {
        await save.erase()
        state = nil
        accountedTokens.removeAll()
        lastResults = []
    }

    /// Equip (or unequip — pass nil) a single cosmetic slot. Persists. Used by
    /// the Wardrobe UI.
    func equipCosmetic(slot: String, name: String?) async {
        guard var current = state else { return }
        current.inventory.equippedCosmetic[slot] = name
        state = current
        await save.write(current)
    }

    /// Purchase an NPC offer. Pure-functional under the hood; persists.
    /// When `haggle` is true, applies a CHA-driven discount on top.
    func buy(from offer: ShopOffer, haggle: Bool = false) async {
        guard let current = state else { return }
        let price = haggle ? NPCInteraction.haggledPrice(offer, cha: current.vitals.stats.cha) : offer.priceGold
        let (next, result) = NPCInteraction.buy(offer, state: current, priceOverride: price)
        guard next != current else { return }
        state = next
        switch result {
        case let .bought(itemId, paidPrice):
            let savings = offer.priceGold - paidPrice
            let body = savings > 0
                ? "Cost: \(paidPrice)g (haggled, saved \(savings)g)"
                : "Cost: \(paidPrice)g"
            notifier?.notify(
                title: "🛒 Bought \(ItemCatalog.label(itemId))",
                body: body,
                kind: .info
            )
        default: break
        }
        await save.write(next)
    }

    /// Fast-travel to a previously-visited region. Pins the region so the
    /// town card shows it even while telemetry from another session fires.
    /// Pass nil to clear the pin and return to "follow the latest event."
    func fastTravel(to region: String?) async {
        guard var current = state else { return }
        current.world.pinnedRegion = region
        if let region {
            current.world.currentRegion = region
        }
        state = current
        if let region {
            notifier?.notify(title: "🧭 Fast-travel", body: "Pinned to \(region)", kind: .info)
        }
        await save.write(current)
    }

    /// Equip a gear item by id.
    func equipGear(_ gearId: String) async {
        guard let current = state else { return }
        let (next, result) = GearAction.equip(gearId, state: current)
        guard next != current else { return }
        state = next
        if case let .equipped(_, name, replaced) = result {
            let body = replaced.map { "Replaced \(GearCatalog.find($0)?.name ?? $0)." } ?? "Now in use."
            notifier?.notify(title: "🎽 Equipped \(name)", body: body, kind: .info)
        }
        await save.write(next)
    }

    /// Unequip a slot. Pure-functional; persists.
    func unequipGear(_ slot: Gear.Slot) async {
        guard let current = state else { return }
        let next = GearAction.unequip(slot: slot, state: current)
        guard next != current else { return }
        state = next
        await save.write(next)
    }

    /// Train a stat at an NPC trainer. Spends EXP.
    func train(_ offering: TrainerOffering) async {
        guard let current = state else { return }
        let (next, result) = NPCInteraction.train(offering, state: current)
        guard next != current else { return }
        state = next
        switch result {
        case let .trained(label, costExp):
            notifier?.notify(
                title: "📈 Trained \(label)",
                body: "Cost: \(costExp) EXP",
                kind: .info
            )
        default: break
        }
        await save.write(next)
    }

    /// Unlock a cosmetic. Idempotent — re-discovering an owned cosmetic is
    /// a no-op (no notification, no save). Used by achievement / quest /
    /// drop hooks to surface "🎀 Unlocked X" toasts.
    func discoverCosmetic(_ id: String, reason: String? = nil) async {
        guard var current = state, let cos = CosmeticCatalog.find(id) else { return }
        var owned = Set(current.inventory.discoveredCosmetics ?? [])
        if owned.contains(id) { return }
        owned.insert(id)
        current.inventory.discoveredCosmetics = Array(owned)
        state = current
        notifier?.notify(
            title: "🎀 Cosmetic unlocked",
            body: reason.map { "\(cos.display) — \($0)" } ?? cos.display,
            kind: .info
        )
        await save.write(current)
    }

    /// Sell one of `itemId` from inventory in exchange for gold. The price is
    /// derived from `ItemCatalog.sellValue` and a notification surfaces the
    /// trade to the player.
    func sellItem(_ itemId: String) async {
        guard var current = state else { return }
        let count = current.inventory.items[itemId] ?? 0
        guard count > 0 else { return }
        let value = ItemCatalog.sellValue(itemId)
        if count <= 1 {
            current.inventory.items.removeValue(forKey: itemId)
        } else {
            current.inventory.items[itemId] = count - 1
        }
        current.progress.gold += value
        state = current
        notifier?.notify(title: "🪙 Sold \(ItemCatalog.label(itemId))", body: "+\(value)g", kind: .info)
        await save.write(current)
    }

    /// Drop one of `itemId` from inventory without compensation.
    func dropItem(_ itemId: String) async {
        guard var current = state else { return }
        let count = current.inventory.items[itemId] ?? 0
        guard count > 0 else { return }
        if count <= 1 {
            current.inventory.items.removeValue(forKey: itemId)
        } else {
            current.inventory.items[itemId] = count - 1
        }
        state = current
        await save.write(current)
    }

    /// Sell one unit of a gear item out of the bag. Price is half the catalog
    /// `priceGold` so dropping rare gear feels worth doing. Equipped gear is
    /// not removed — only inventory copies.
    func sellGear(_ gearId: String) async {
        guard var current = state else { return }
        guard let def = GearCatalog.find(gearId) else { return }
        let count = current.inventory.items[gearId] ?? 0
        guard count > 0 else { return }
        let value = max(1, def.priceGold / 2)
        if count <= 1 {
            current.inventory.items.removeValue(forKey: gearId)
        } else {
            current.inventory.items[gearId] = count - 1
        }
        current.progress.gold += value
        state = current
        notifier?.notify(title: "🪙 Sold \(def.glyph) \(def.name)", body: "+\(value)g", kind: .info)
        await save.write(current)
    }

    /// Consume one of `itemId` from the inventory and apply its effect. The
    /// effect is recorded in `lastResults` for UI feedback.
    func useItem(_ itemId: String) async {
        guard let current = state else { return }
        var (next, result) = ItemUsage.use(itemId, state: current)
        guard next != current else { return }
        // Recovery is atomic with feeding (issue #38): if the heal pushed HP
        // back above zero, clear the critical stamp here rather than waiting
        // for the next store tick's `advanceCriticalClock`. Otherwise a fresh
        // event that re-drops HP to 0 before that tick could resume a stale
        // `criticalSince` near the death threshold.
        if next.vitals.hp > 0, next.criticalSince != nil {
            next.criticalSince = nil
        }
        state = next
        switch result {
        case let .healed(hp):
            lastResults = [.hpChanged(delta: hp)]
        case let .restoredSP(sp):
            lastResults = [.spChanged(delta: sp)]
        case let .statRaised(stat, delta):
            lastResults = [.statBoost(stat: stat, delta: delta)]
        case let .sold(gold):
            // Surface as a plain ageAdvanced-style toast; gold change is in state.
            lastResults = [.itemDropped(itemId: "sold-for-\(gold)g", count: 1)]
        case .missing, .unknown:
            break
        }
        await save.write(next)
    }

    // MARK: - Tick

    /// Apply any new tokens in `events` to the pet. Idempotent across re-reads
    /// of the JSONL — only the *delta* of tokens since last seen is consumed.
    /// `usedPercentage` is the live 5-hour rate-limit budget consumption, used
    /// for plan-normalized HP drain + aging (nil → skip wear this tick).
    func tick(against events: [UsageEvent], usedPercentage: Double? = nil) async {
        guard var current = state else { return }
        // First tick after a hatch: snapshot the current state of telemetry
        // and don't apply anything. From the next tick onward only true
        // deltas (events that grew, or events that arrived since hatching)
        // affect the pet.
        if pendingSeed {
            for e in events {
                accountedTokens[eventKey(e)] = e.grandTotal
            }
            // Even though we don't apply HP/age effects on this seeding tick,
            // populate the current region from the most-recent event so the
            // town card has something to render before the player's next
            // Claude message arrives.
            if let mostRecent = events.last(where: { $0.cwd != nil }), let cwd = mostRecent.cwd {
                let region = Region.identifier(for: cwd)
                let flavor = Region.flavor(for: cwd)
                current.world.currentRegion = region
                if current.world.flavors == nil { current.world.flavors = [:] }
                current.world.flavors?[region] = flavor
                state = current
                await save.write(current)
            }
            pendingSeed = false
            return
        }
        var newResults: [TickResult] = []
        // Plan-normalized wear: HP drain + aging keyed off Δ% of the
        // 5-hour rate-limit budget. Done once per tick batch (not per
        // event) so all plans tick at similar wall-clock cadence — then
        // modulated by the model mix consumed this tick so Opus-heavy work
        // ages the pet faster than Haiku-heavy work (issue #36).
        let mix = TickProcessor.modelMix(for: events)
        let (afterWear, wearResults) = TickProcessor.applyBudgetWear(
            state: current,
            usedPercentage: usedPercentage,
            modelMix: mix
        )
        current = afterWear
        newResults.append(contentsOf: wearResults)
        for e in events {
            let key = eventKey(e)
            let already = accountedTokens[key, default: 0]
            let delta = e.grandTotal - already
            if delta <= 0 { continue }
            // Auto-play forces passive combat so encounters from telemetry
            // resolve instantly instead of blocking on a modal the player
            // never sees.
            let effectiveMode: CombatMode = (notifier?.autoPlay == true)
                ? .passive
                : (notifier?.combatMode ?? .passive)
            let (next, results) = TickProcessor.process(e, state: current, deltaTokens: delta, combatMode: effectiveMode)
            current = next
            accountedTokens[key] = e.grandTotal
            newResults.append(contentsOf: results)
        }
        // Update quest telemetry from results before persistence so any
        // completion checks reflect the freshest counters. Also drop random
        // gear on passive-mode victories (~33% chance).
        for r in newResults {
            switch r {
            case let .encounter(_, .victory(_, gold)):
                current.questTelemetryOrEmpty.monstersDefeated += 1
                current.questTelemetryOrEmpty.cumulativeGold += gold
                if Int.random(in: 1...3) == 1 {
                    let atk = current.effectiveStats.str + current.effectiveStats.dex / 2 + current.gearAttackBonus
                    if let drop = GearCatalog.randomDrop(playerATK: atk) {
                        current.inventory.items[drop.id, default: 0] += 1
                        notifier?.notify(title: "🎁 Gear drop", body: "\(drop.glyph) \(drop.name)", kind: .info)
                    }
                }
                // Cosmetic drop check — one per victory, weighted by rarity.
                // Only undiscovered cosmetics are eligible, so the player
                // can't waste a roll on something they already own.
                if let dropped = rollCosmeticDrop(state: current) {
                    var owned = Set(current.inventory.discoveredCosmetics ?? [])
                    owned.insert(dropped.id)
                    current.inventory.discoveredCosmetics = Array(owned)
                    notifier?.notify(
                        title: "🎀 Cosmetic dropped",
                        body: "\(dropped.display) — found in the spoils.",
                        kind: .info
                    )
                }
            default: break
            }
        }
        for e in events {
            for t in e.tools {
                current.questTelemetryOrEmpty.toolCounts[t, default: 0] += 1
            }
        }
        // Advance the wall-clock critical/death clock every tick — including
        // ticks where no new Claude usage arrived — so a downed pet still
        // dies after the grace period (or recovers if it was fed) while the
        // player is idle (issue #37).
        let (afterCritical, criticalResults) = TickProcessor.advanceCriticalClock(state: current)
        current = afterCritical
        newResults.append(contentsOf: criticalResults)

        // Re-evaluate active quests so the UI shows progress + completion.
        current = QuestEngine.evaluate(state: current, telemetry: current.questTelemetryOrEmpty)

        // Cosmetic unlocks tied to achievements that just fired. Adding
        // them inline so the same tick that earned the achievement also
        // gets the cosmetic — and the in-game toast pair feels connected.
        for r in newResults {
            if case let .achievementEarned(id) = r,
               let cos = CosmeticCatalog.cosmetic(forAchievementId: id) {
                var owned = Set(current.inventory.discoveredCosmetics ?? [])
                if !owned.contains(cos.id) {
                    owned.insert(cos.id)
                    current.inventory.discoveredCosmetics = Array(owned)
                }
            }
        }

        if current != state {
            state = current
            lastResults = newResults
            await save.write(current)
            // Cosmetic verb flavor (issue #41): the dominant tool family this
            // tick enriches the existing (already rate-limited) drop toast —
            // no extra toast, no mechanical effect.
            announce(newResults, toolVerb: dominantToolVerb(for: events))
        }
        // Idle autopilot: one decision per tick, after telemetry. Lets the pet
        // self-sustain when the player isn't actively babysitting it.
        if notifier?.autoPlay == true {
            await runAutoPlayStep()
        }
    }

    /// Take a single autopilot action if one is warranted. Called at the tail
    /// of every tick when auto-play is enabled.
    private func runAutoPlayStep() async {
        guard let current = state, current.deathState == nil else { return }
        guard let action = AutoPlay.chooseAction(state: current) else { return }
        switch action {
        case let .useItem(id):
            await useItem(id)
            notifier?.notify(
                title: "🤖 Auto-play",
                body: "Ate \(ItemCatalog.label(id))",
                kind: .info
            )
        case let .buyOffer(itemId, priceGold):
            await buy(from: ShopOffer(itemId: itemId, priceGold: priceGold))
        case let .acceptQuest(questId):
            guard let quest = QuestCatalog.byId(questId) else { return }
            await acceptQuest(quest)
        case let .claimQuest(questId):
            guard let quest = QuestCatalog.byId(questId) else { return }
            await claimQuest(quest)
        case .combatAttack:
            await combatAttack()
        case let .combatHeal(id):
            await combatUseItem(id)
        case .dismissOutcome:
            await dismissBattleOutcome()
        case .wander:
            await wanderForEncounter()
        case let .equipGear(id):
            await equipGear(id)
            if let g = GearCatalog.find(id) {
                notifier?.notify(
                    title: "🤖 Auto-play",
                    body: "Equipped \(g.glyph) \(g.name)",
                    kind: .info
                )
            }
        case let .travel(region):
            await fastTravel(to: region)
            notifier?.notify(
                title: "🤖 Auto-play",
                body: "Traveled to \(region) — more quests available.",
                kind: .info
            )
        case let .combatCast(skillId):
            await combatCastSkill(skillId)
        case .combatFlee:
            await combatFlee()
            notifier?.notify(
                title: "🤖 Auto-play",
                body: "Fled the fight — too injured to continue.",
                kind: .warning
            )
        case .enterDungeon:
            await enterDungeon()
        case let .trainStat(offering):
            await train(offering)
        case let .trainSkill(offering):
            await train(offering)
        }
    }

    /// Accept a quest from an NPC. The quest enters active state and starts
    /// being tracked on subsequent ticks.
    func acceptQuest(_ quest: Quest) async {
        guard let current = state else { return }
        let (next, result) = QuestEngine.accept(quest, state: current)
        guard next != current else { return }
        state = next
        if result == .accepted {
            notifier?.notify(title: "📜 Quest accepted", body: quest.name, kind: .info)
        }
        await save.write(next)
    }

    /// Claim a completed quest's reward.
    func claimQuest(_ quest: Quest) async {
        guard let current = state else { return }
        let (after, result) = QuestEngine.claim(quest, state: current)
        guard after != current else { return }
        var next = after
        // Quest-gated cosmetic unlock — single source of truth for which
        // cosmetic (if any) this quest grants lives in CosmeticCatalog.
        if let cos = CosmeticCatalog.cosmetic(forQuestId: quest.id) {
            var owned = Set(next.inventory.discoveredCosmetics ?? [])
            if !owned.contains(cos.id) {
                owned.insert(cos.id)
                next.inventory.discoveredCosmetics = Array(owned)
                notifier?.notify(
                    title: "🎀 Cosmetic unlocked",
                    body: "\(cos.display) — \(quest.name) reward.",
                    kind: .info
                )
            }
        }
        state = next
        if case let .claimed(gold, exp, item) = result {
            let extras = item.map { " + \(ItemCatalog.label($0))" } ?? ""
            notifier?.notify(
                title: "🏆 \(quest.name) complete",
                body: "+\(gold)g, +\(exp) EXP\(extras)",
                kind: .info
            )
        }
        await save.write(next)
    }

    /// Surface the most notable results to the notifier. Item drops are batched
    /// (one notification per tick with a summary) so the player doesn't get
    /// spammed.
    /// The verb for the most-used tool family across this tick's events, used
    /// only to flavor the drop toast (issue #41). Returns nil when no event
    /// carried a tool with a themed verb.
    private func dominantToolVerb(for events: [UsageEvent]) -> String? {
        var counts: [String: Int] = [:]
        for e in events {
            for t in e.tools {
                if let verb = TickProcessor.toolVerb(for: t) {
                    counts[verb, default: 0] += 1
                }
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private func announce(_ results: [TickResult], toolVerb: String? = nil) {
        guard let notifier else { return }
        var dropCount = 0
        var firstDrop: String?
        for r in results {
            switch r {
            case let .itemDropped(id, count):
                dropCount += count
                if firstDrop == nil { firstDrop = ItemCatalog.label(id) }
            case let .achievementEarned(id):
                let title = AchievementCatalog.byId[id]?.title ?? id
                notifier.notify(title: "🏅 \(title)", body: "Achievement unlocked", kind: .info)
            case let .encounter(name, .victory(exp, gold)):
                notifier.notify(title: "⚔️ Defeated \(name)", body: "+\(exp) EXP, +\(gold)g", kind: .info)
            case .enteredCritical:
                let nm = state?.identity.name ?? "Your Tokegotchi"
                notifier.notify(
                    title: "💀 \(nm) is critical",
                    body: "Use a food item before time runs out.",
                    kind: .danger
                )
            case let .died(cause):
                let nm = state?.identity.name ?? "Your Tokegotchi"
                notifier.notify(
                    title: "🪦 \(nm) has passed",
                    body: cause == .natural ? "Died of old age." : "Fell in critical state.",
                    kind: .danger
                )
            default:
                break
            }
        }
        if dropCount > 0, let firstDrop {
            let extra = dropCount > 1 ? " (+\(dropCount - 1) more)" : ""
            // Prefix the verb flavor when this tick's work had a dominant tool
            // family (e.g. "While you forge — ") — purely cosmetic.
            let prefix = toolVerb.map { "While you \($0) — " } ?? ""
            notifier.notify(title: "Drop", body: "\(prefix)\(firstDrop)\(extra)", kind: .info)
        }
    }

    /// Player opened the tab — clear any pending badge.
    func acknowledgeUnseen() {
        notifier?.clearUnseen()
    }

    // MARK: - Wander (player-initiated random encounter)

    /// Spawn a random-tier encounter on demand so the player has something
    /// to do regardless of region discovery state or event cadence.
    func wanderForEncounter() async {
        guard var current = state, current.activeBattle == nil else { return }
        guard let region = current.world.currentRegion else { return }
        let flavor = current.world.flavors?[region] ?? .wilderness
        let salt = current.world.eventCounts?[region] ?? Int.random(in: 0...1000)
        guard let monster = EncounterEngine.choose(
            for: flavor, playerStats: current.vitals.stats, salt: salt, tier: .random
        ) else { return }
        // Auto-play forces passive combat — fights resolve instantly so the
        // autopilot never gets stuck waiting for a manual Attack press.
        let mode: CombatMode = (notifier?.autoPlay == true) ? .passive : (notifier?.combatMode ?? .passive)
        if mode == .active {
            current.activeBattle = ActiveBattle(encounter: monster)
            current.activeBattle?.log = ["You wander the trails — \(monster.monsterName) appears!"]
            state = current
            notifier?.notify(title: "🚶 \(monster.monsterName) appears", body: "Active battle started.", kind: .info)
        } else {
            let (afterFight, outcome) = EncounterEngine.resolve(monster, against: current)
            current = afterFight
            state = current
            switch outcome {
            case let .victory(exp, gold):
                notifier?.notify(title: "⚔️ Wander victory", body: "Defeated \(monster.monsterName) — +\(exp) EXP, +\(gold)g", kind: .info)
                current.questTelemetryOrEmpty.monstersDefeated += 1
                current.questTelemetryOrEmpty.cumulativeGold += gold
            case .fled:
                notifier?.notify(title: "🏃 Wander retreat", body: "\(monster.monsterName) was too strong.", kind: .warning)
            }
        }
        await save.write(current)
    }

    // MARK: - Dungeons

    /// Force an encounter against the current region's boss monster.
    /// Respects combat mode (passive auto-resolves, active opens the modal).
    /// Has no cost — the implicit cost is the HP loss during the fight.
    func enterDungeon() async {
        guard var current = state, current.activeBattle == nil else { return }
        guard let region = current.world.currentRegion else { return }
        let flavor = current.world.flavors?[region] ?? .wilderness
        guard let monster = EncounterEngine.choose(
            for: flavor, playerStats: current.vitals.stats, salt: 0, tier: .dungeon
        ) else { return }
        // Auto-play forces passive combat — fights resolve instantly so the
        // autopilot never gets stuck waiting for a manual Attack press.
        let mode: CombatMode = (notifier?.autoPlay == true) ? .passive : (notifier?.combatMode ?? .passive)
        if mode == .active {
            current.activeBattle = ActiveBattle(encounter: monster)
            // Reskin the opening log so the player knows this is a dungeon.
            current.activeBattle?.log = ["You step into the dungeon. \(monster.monsterName) blocks the way!"]
            state = current
            notifier?.notify(
                title: "🏰 Dungeon: \(monster.monsterName)",
                body: "Active battle started.",
                kind: .warning
            )
        } else {
            let (afterFight, outcome) = EncounterEngine.resolve(monster, against: current)
            current = afterFight
            state = current
            switch outcome {
            case let .victory(exp, gold):
                notifier?.notify(title: "🏰 Dungeon cleared", body: "Defeated \(monster.monsterName) — +\(exp) EXP, +\(gold)g", kind: .info)
                current.questTelemetryOrEmpty.monstersDefeated += 1
                current.questTelemetryOrEmpty.cumulativeGold += gold
            case .fled:
                notifier?.notify(title: "🏰 Dungeon retreat", body: "\(monster.monsterName) was too strong.", kind: .warning)
            }
        }
        await save.write(current)
    }

    // MARK: - Active combat

    /// Combat actions used by the in-panel ActiveBattleCard.
    func combatAttack() async {
        await runCombat(.attack)
    }

    func combatUseItem(_ itemId: String) async {
        await runCombat(.useItem(itemId))
    }

    func combatFlee() async {
        await runCombat(.flee)
    }

    func combatCastSkill(_ skillId: String) async {
        await runCombat(.skill(skillId))
    }

    private enum CombatAction {
        case attack
        case useItem(String)
        case flee
        case skill(String)
    }

    /// Dismiss the battle outcome dialog (clears `activeBattle`).
    func dismissBattleOutcome() async {
        guard var current = state else { return }
        current.activeBattle = nil
        state = current
        await save.write(current)
    }

    private func runCombat(_ action: CombatAction) async {
        guard let current = state, let battle = current.activeBattle,
              battle.resolvedOutcome == nil else { return }
        let outcome: (TokegotchiState, ActiveBattle?, CombatRoundResult)
        switch action {
        case .attack:
            outcome = CombatEngine.attack(state: current, battle: battle)
        case let .useItem(id):
            outcome = CombatEngine.useItem(id, state: current, battle: battle)
        case .flee:
            outcome = CombatEngine.flee(state: current, battle: battle)
        case let .skill(skillId):
            guard let skill = SkillCatalog.find(skillId) else { return }
            outcome = SkillResolution.cast(skill, state: current, battle: battle)
        }
        var saved = outcome.0
        // Engine always returns the final battle (with full log). When the
        // round resolves, stamp the outcome so the UI can show a dismissable
        // dialog with the closing log entries intact.
        var finalBattle = outcome.1 ?? battle
        switch outcome.2 {
        case .victory:
            finalBattle.monsterHP = 0
            finalBattle.resolvedOutcome = .victory
        case .fled:
            finalBattle.resolvedOutcome = .fled
        case .playerDown:
            finalBattle.resolvedOutcome = .playerDown
        case .ongoing:
            break
        }
        saved.activeBattle = finalBattle
        state = saved
        switch outcome.2 {
        case let .victory(exp, gold):
            notifier?.notify(title: "⚔️ Victory", body: "+\(exp) EXP, +\(gold)g", kind: .info)
            saved.questTelemetryOrEmpty.monstersDefeated += 1
            saved.questTelemetryOrEmpty.cumulativeGold += gold
            // Active-mode victories also have a gear drop chance.
            if Int.random(in: 1...3) == 1 {
                let atk = saved.effectiveStats.str + saved.effectiveStats.dex / 2 + saved.gearAttackBonus
                if let drop = GearCatalog.randomDrop(playerATK: atk) {
                    saved.inventory.items[drop.id, default: 0] += 1
                    state = saved
                    notifier?.notify(title: "🎁 Gear drop", body: "\(drop.glyph) \(drop.name)", kind: .info)
                }
            }
        case .fled:
            notifier?.notify(title: "🏃 Fled", body: "Escaped the encounter.", kind: .info)
        case .playerDown:
            notifier?.notify(title: "💀 Knocked down", body: "Your pet is in critical state.", kind: .danger)
        case .ongoing:
            break
        }
        await save.write(saved)
    }

    // Test seam — let tests stage a known state without going through the
    // public API. Not exposed in user-facing code paths.
    #if DEBUG
        func setStateForTesting(_ s: TokegotchiState) {
            state = s
        }
    #endif

    /// Roll the per-victory cosmetic drop. Weighted by rarity and gated to
    /// undiscovered cosmetics only. Returns nil for the common case where
    /// nothing drops.
    private func rollCosmeticDrop(state: TokegotchiState) -> Cosmetic? {
        let owned = Set(state.inventory.discoveredCosmetics ?? [])
        let pool = CosmeticCatalog.dropPool.filter { !owned.contains($0.id) }
        guard !pool.isEmpty else { return nil }
        // Two-stage roll so each cosmetic's `rarity.weight` is honored.
        // First decide whether *anything* drops (sum of weights, capped at 1),
        // then pick one weighted by its rarity within the remaining pool.
        let totalWeight = pool.reduce(0.0) { $0 + $1.unlock.dropWeight }
        let dropChance = min(0.95, totalWeight)
        guard Double.random(in: 0..<1) < dropChance else { return nil }
        var r = Double.random(in: 0..<totalWeight)
        for c in pool {
            r -= c.unlock.dropWeight
            if r <= 0 { return c }
        }
        return pool.last
    }

    private func eventKey(_ e: UsageEvent) -> String {
        // messageId disambiguates when present; fall back to ISO timestamp.
        if let mid = e.messageId, !mid.isEmpty { return mid }
        return "ts:\(e.timestamp.timeIntervalSince1970):\(e.model)"
    }
}

import Foundation

/// Idle "the game plays itself" autopilot. When enabled in settings, runs
/// after each tick and tries to:
/// - Eat food if HP is below ~75%
/// - Drink an SP potion if SP is empty mid-battle
/// - Claim any completed quests
/// - Top up food when supply is low (buy if HP < 75% or no food at all)
/// - Wander into a random encounter when healthy, so EXP/gold keeps flowing
/// - Auto-pick Attack in active battles (so the pet never sits stuck)
/// - Dismiss battle outcome dialogs so loops continue
///
/// Pure decision-making lives here; the store applies the chosen action.
enum AutoPlay {
    enum Action: Equatable {
        case useItem(String)
        case buyOffer(itemId: String, priceGold: Int)
        case acceptQuest(String)
        case claimQuest(String)
        case combatAttack
        case combatHeal(String)        // use a healing item mid-combat
        case combatCast(skillId: String) // cast a learned damage/heal skill
        case combatFlee                  // run when survival is unlikely
        case dismissOutcome
        case wander                    // trigger a random encounter
        case enterDungeon              // boss fight when overpowered for the region
        case equipGear(String)         // swap in a better item from the bag
        case travel(region: String)    // fast-travel for strategic reasons
        case trainStat(offering: TrainerOffering)
        case trainSkill(offering: TrainerOffering)
    }

    /// Heal threshold out of combat. Tuned generous so the pet keeps itself
    /// near full HP between fights — feeding when food is on hand should
    /// look proactive to the player, not last-ditch.
    static let healThreshold: Double = 0.75
    /// Below this we'll spend gold to buy food even if a fight isn't imminent.
    static let buyThreshold: Double = 0.85
    /// At or above this we feel safe enough to go pick a fight for EXP/gold.
    static let wanderThreshold: Double = 0.85
    /// Keep at least this many food items on hand. Buys to refill when below.
    static let minFoodStock: Int = 2

    /// Return the next high-priority action the autopilot wants to take, or
    /// nil if there's nothing to do. Caller applies it.
    static func chooseAction(state: TokegotchiState) -> Action? {
        // Always clear outcome dialogs so battles don't block the loop.
        if let b = state.activeBattle, b.resolvedOutcome != nil {
            return .dismissOutcome
        }

        // In active combat: priority cascade
        //   1. Heal if HP critical and we have food
        //   2. Flee if HP < 15% and no heal item available (better to live)
        //   3. Cast a damage/heal skill if SP permits + skill is learned
        //   4. Otherwise plain attack
        if let battle = state.activeBattle {
            let hpPct = Double(state.vitals.hp) / Double(max(state.vitals.hpMax, 1))
            if hpPct < 0.35, let healId = bestHealItem(in: state.inventory.items) {
                return .combatHeal(healId)
            }
            if hpPct < 0.15 && bestHealItem(in: state.inventory.items) == nil {
                return .combatFlee
            }
            if let skillId = bestCombatSkill(state: state, battle: battle) {
                return .combatCast(skillId: skillId)
            }
            return .combatAttack
        }

        // Out of combat: claim completed quests first (immediate payoff).
        if let completed = QuestEngine.active(state: state).first(where: { $0.completed }) {
            return .claimQuest(completed.questId)
        }
        // Upgrade gear when the bag has something strictly better than
        // what's currently equipped. Cheap to compute and a free power up.
        if let upgrade = bestGearUpgrade(state: state) {
            return .equipGear(upgrade)
        }
        // Then accept any quest available in the current region that we
        // don't already have active or claimed. Auto-play is meant to be
        // hands-off — quests are a primary progression loop, so the
        // autopilot should opt in to them just like a player would.
        if let region = state.world.currentRegion {
            let flavor = state.world.flavors?[region] ?? .wilderness
            let activeIds = Set(QuestEngine.active(state: state).map(\.questId))
            let claimedIds = Set(state.inventory.completedQuestIds ?? [])
            if let next = QuestCatalog.quests(for: flavor).first(where: {
                !activeIds.contains($0.id) && !claimedIds.contains($0.id)
            }) {
                return .acceptQuest(next.id)
            }
        }
        // Spend banked EXP on training. Stat boosts when we have headroom,
        // then skill learns (one-shot, big payoff). Conservative — only fire
        // when we have ≥2× the cost banked so a single Train doesn't drain
        // our entire EXP wallet.
        if let train = bestTraining(state: state) {
            switch train.effect {
            case .statBoost, .healMax:
                return .trainStat(offering: train)
            case .learnSkill:
                return .trainSkill(offering: train)
            }
        }
        // Buy gear from a local merchant if it's an upgrade AND affordable.
        // Limits the spend so the autopilot doesn't blow all gold at once
        // on a luxury item.
        if let offer = bestGearOffer(state: state) {
            return .buyOffer(itemId: offer.itemId, priceGold: offer.priceGold)
        }
        // Top up SP potions if we know skills and SP is mostly empty.
        let spPct = Double(state.vitals.sp) / Double(max(state.vitals.spMax, 1))
        if !state.inventory.skillsLearned.isEmpty, spPct < 0.4,
           let spOffer = cheapestSPPotionOffer(state: state),
           state.progress.gold >= spOffer.priceGold * 2
        {
            return .buyOffer(itemId: spOffer.itemId, priceGold: spOffer.priceGold)
        }
        // Strategic travel: if the current region has no unclaimed quests
        // AND we have a visited region that DOES, hop over there. Keeps
        // auto-play progressing through quest content rather than grinding
        // the same exhausted region forever.
        if let target = betterRegion(state: state) {
            return .travel(region: target)
        }

        let hpPct = Double(state.vitals.hp) / Double(max(state.vitals.hpMax, 1))
        let foodCount = totalFoodCount(state.inventory.items)

        // Run the dungeon when we're overpowered for the region. Gated on
        // HP being near-full so we don't suicide-charge a boss after a
        // hard fight.
        if hpPct >= 0.85, dungeonAdvisable(state: state) {
            return .enterDungeon
        }

        // Heal up if HP is below threshold and we have food on hand.
        if hpPct < healThreshold, let healId = bestHealItem(in: state.inventory.items) {
            return .useItem(healId)
        }

        // Buy food when stock is low. Two triggers:
        //   - We need to heal but have no food
        //   - Pantry is below minFoodStock and we can afford the cheapest food
        let needFoodNow  = hpPct < buyThreshold && foodCount == 0
        let needFoodSoon = foodCount < minFoodStock
        if needFoodNow || needFoodSoon,
           let offer = cheapestAvailableHealOffer(state: state),
           state.progress.gold >= offer.priceGold
        {
            return .buyOffer(itemId: offer.itemId, priceGold: offer.priceGold)
        }

        // Healthy and nothing pressing? Go grind a fight for EXP/gold.
        if hpPct >= wanderThreshold, state.world.currentRegion != nil {
            return .wander
        }

        return nil
    }

    /// Pick the smallest food item the player has, so we don't waste a feast
    /// when bread would do.
    private static func bestHealItem(in items: [String: Int]) -> String? {
        let order = ["bread", "hearty-meat", "feast"]
        for id in order where (items[id] ?? 0) > 0 { return id }
        return nil
    }

    /// Sum of all food items the player is carrying.
    private static func totalFoodCount(_ items: [String: Int]) -> Int {
        let order = ["bread", "hearty-meat", "feast"]
        return order.reduce(0) { $0 + (items[$1] ?? 0) }
    }

    /// Score a piece of gear: higher = better. Sums attack/defense bonuses
    /// plus the magnitude of its stat bonuses so support gear (CHA staffs,
    /// INT scrolls) doesn't get dismissed against pure damage gear.
    private static func gearScore(_ g: Gear) -> Int {
        let stat = abs(g.statBonus.str) + abs(g.statBonus.dex)
                 + abs(g.statBonus.int) + abs(g.statBonus.agi)
                 + abs(g.statBonus.cha)
        return g.attackBonus + g.defenseBonus + stat
    }

    /// Per slot, find the highest-scored gear in the bag that beats the
    /// currently-equipped piece. Returns the id of the winning gear or nil
    /// if nothing in the bag is an upgrade.
    private static func bestGearUpgrade(state: TokegotchiState) -> String? {
        // Bag = inventory items whose ids match gear catalog entries.
        let owned: [(Gear, Int)] = GearCatalog.all.compactMap { g in
            let n = state.inventory.items[g.id] ?? 0
            return n > 0 ? (g, n) : nil
        }
        guard !owned.isEmpty else { return nil }
        var bestUpgrade: (Gear, Int)? = nil  // (gear, delta over current)
        for slot in Gear.Slot.allCases {
            let currentScore: Int = {
                if let id = state.inventory.equippedGear[slot.rawValue] ?? nil,
                   let g = GearCatalog.find(id)
                {
                    return gearScore(g)
                }
                return 0
            }()
            for (g, _) in owned where g.slot == slot {
                let s = gearScore(g)
                let delta = s - currentScore
                if delta > 0 && (bestUpgrade.map { delta > $0.1 } ?? true) {
                    bestUpgrade = (g, delta)
                }
            }
        }
        return bestUpgrade?.0.id
    }

    /// Pick a visited region that has unclaimed quest content if the
    /// current region is exhausted. Returns nil when staying put is fine.
    private static func betterRegion(state: TokegotchiState) -> String? {
        guard let currentRegion = state.world.currentRegion else { return nil }
        let claimedIds = Set(state.inventory.completedQuestIds ?? [])
        let activeIds = Set(QuestEngine.active(state: state).map(\.questId))

        func hasOpenQuests(in region: String) -> Bool {
            let flavor = state.world.flavors?[region] ?? .wilderness
            return QuestCatalog.quests(for: flavor).contains { q in
                !claimedIds.contains(q.id) && !activeIds.contains(q.id)
            }
        }

        // Only travel if the current region is genuinely exhausted.
        guard !hasOpenQuests(in: currentRegion) else { return nil }
        let visited = (state.world.flavors ?? [:]).keys.sorted()
        return visited.first { $0 != currentRegion && hasOpenQuests(in: $0) }
    }

    /// Best learned damage/heal skill to cast right now, or nil to fall
    /// back to plain attack. Picks a heal when HP is below 70%, otherwise
    /// the highest-damage skill the pet can afford in SP. Block / escape
    /// / weaken are too situational for the autopilot.
    private static func bestCombatSkill(
        state: TokegotchiState,
        battle: ActiveBattle
    ) -> String? {
        let sp = state.vitals.sp
        let hpPct = Double(state.vitals.hp) / Double(max(state.vitals.hpMax, 1))
        let learned = state.inventory.skillsLearned.compactMap { SkillCatalog.find($0) }
        guard !learned.isEmpty else { return nil }
        // Pre-pick a heal skill if available and HP-needy.
        if hpPct < 0.70 {
            let heals = learned.filter {
                if case .heal = $0.effect { return true } else { return false }
            }
            if let heal = heals.sorted(by: { $0.spCost < $1.spCost }).first(where: { $0.spCost <= sp }) {
                return heal.id
            }
        }
        // Otherwise pick the priciest damage skill we can pay for (proxy
        // for "biggest hit"). Skip if monster HP is low enough that a
        // basic attack ends it — saves SP.
        let damageSkills = learned.filter {
            if case .damage = $0.effect { return true } else { return false }
        }
        let eff = state.effectiveStats
        let basicAttack = max(1, eff.str + eff.dex / 2 + state.gearAttackBonus)
        let basicDamagePerHit = max(1, basicAttack - battle.monsterDefense)
        if battle.monsterHP <= basicDamagePerHit { return nil }
        let best = damageSkills
            .filter { $0.spCost <= sp }
            .sorted { $0.spCost > $1.spCost }
            .first
        return best?.id
    }

    /// Decide whether attacking the boss is sane. The dungeon engine picks
    /// the region's hardest monster + buffs it; we only want to enter when
    /// the pet meaningfully out-stats it.
    private static func dungeonAdvisable(state: TokegotchiState) -> Bool {
        guard let region = state.world.currentRegion else { return false }
        let flavor = state.world.flavors?[region] ?? .wilderness
        let steps = state.world.regionSteps?[region] ?? 0
        // Dungeon must be unlocked.
        guard Region.Discovery.unlocked(forSteps: steps).contains(.dungeon) else { return false }
        guard let boss = EncounterEngine.choose(
            for: flavor, playerStats: state.vitals.stats, salt: 0, tier: .dungeon
        ) else { return false }
        let eff = state.effectiveStats
        let attack = max(1, eff.str + eff.dex / 2 + state.gearAttackBonus)
        // Need to kill in ≤ 4 turns AND take ≤ 1/3 hpMax across the fight.
        let dpsAttack = max(1, attack - boss.defense)
        let turnsToKill = (boss.hp + dpsAttack - 1) / dpsAttack
        guard turnsToKill <= 4 else { return false }
        let playerDef = eff.dex / 2 + state.gearDefenseBonus
        let damageTaken = max(1, boss.attack - playerDef)
        let totalDamage = damageTaken * max(0, turnsToKill - 1)
        return totalDamage * 3 <= state.vitals.hpMax
    }

    /// Highest-impact training offering we can comfortably afford. Returns
    /// nil if EXP is tight or every offering would over-spend.
    private static func bestTraining(state: TokegotchiState) -> TrainerOffering? {
        guard let region = state.world.currentRegion else { return nil }
        let flavor = state.world.flavors?[region] ?? .wilderness
        let steps = state.world.regionSteps?[region] ?? 0
        // Trainers unlock at the village discovery threshold.
        guard Region.Discovery.unlocked(forSteps: steps).contains(.village) else { return nil }
        let exp = state.progress.exp
        let learned = Set(state.inventory.skillsLearned)
        // Two passes: prefer skills (one-shot, biggest upside) we don't yet
        // know, then stat boosts. Both require ≥2× cost in the bank so we
        // don't bottom-out EXP.
        for npc in NPCRoster.npcs(for: flavor) {
            if case let .trainer(offerings) = npc.role {
                for o in offerings {
                    if case let .learnSkill(id) = o.effect,
                       !learned.contains(id),
                       exp >= o.priceExp * 2
                    {
                        return o
                    }
                }
            }
        }
        for npc in NPCRoster.npcs(for: flavor) {
            if case let .trainer(offerings) = npc.role {
                for o in offerings {
                    if case .statBoost = o.effect, exp >= o.priceExp * 2 {
                        return o
                    }
                    if case .healMax = o.effect, exp >= o.priceExp * 2 {
                        return o
                    }
                }
            }
        }
        return nil
    }

    /// Best affordable gear offer on the current region's merchant — i.e.,
    /// something that would beat what's currently equipped in its slot.
    /// Conservative on spend: caller must keep enough gold for several
    /// food purchases afterward.
    private static func bestGearOffer(state: TokegotchiState) -> ShopOffer? {
        guard let region = state.world.currentRegion else { return nil }
        let flavor = state.world.flavors?[region] ?? .wilderness
        // Reserve enough gold for food + an SP top-up after gear spending.
        let reserve = 50
        guard state.progress.gold > reserve else { return nil }
        var best: (ShopOffer, Int)?
        for npc in NPCRoster.npcs(for: flavor) {
            if case let .merchant(stock) = npc.role {
                for offer in stock {
                    guard let g = GearCatalog.find(offer.itemId) else { continue }
                    let cur: Int = {
                        if let id = state.inventory.equippedGear[g.slot.rawValue] ?? nil,
                           let eg = GearCatalog.find(id)
                        {
                            return gearOfferScore(eg)
                        }
                        return 0
                    }()
                    let delta = gearOfferScore(g) - cur
                    if delta > 0,
                       state.progress.gold - offer.priceGold >= reserve,
                       (best.map { delta > $0.1 } ?? true)
                    {
                        best = (offer, delta)
                    }
                }
            }
        }
        return best?.0
    }

    private static func gearOfferScore(_ g: Gear) -> Int {
        g.attackBonus + g.defenseBonus
            + abs(g.statBonus.str) + abs(g.statBonus.dex)
            + abs(g.statBonus.int) + abs(g.statBonus.agi) + abs(g.statBonus.cha)
    }

    /// Cheapest SP-potion offer in the current region.
    private static func cheapestSPPotionOffer(state: TokegotchiState) -> ShopOffer? {
        guard let region = state.world.currentRegion else { return nil }
        let flavor = state.world.flavors?[region] ?? .wilderness
        var best: ShopOffer?
        for npc in NPCRoster.npcs(for: flavor) {
            if case let .merchant(stock) = npc.role {
                for offer in stock {
                    if case .spPotion = ItemCatalog.find(offer.itemId)?.kind {
                        if best == nil || offer.priceGold < (best?.priceGold ?? Int.max) {
                            best = offer
                        }
                    }
                }
            }
        }
        return best
    }

    /// Find the cheapest food item across NPCs in the current region.
    private static func cheapestAvailableHealOffer(state: TokegotchiState) -> ShopOffer? {
        guard let region = state.world.currentRegion else { return nil }
        let flavor = state.world.flavors?[region] ?? .wilderness
        var best: ShopOffer?
        for npc in NPCRoster.npcs(for: flavor) {
            if case let .merchant(stock) = npc.role {
                for offer in stock {
                    if case .food = ItemCatalog.find(offer.itemId)?.kind {
                        if best == nil || offer.priceGold < (best?.priceGold ?? Int.max) {
                            best = offer
                        }
                    }
                }
            }
        }
        return best
    }
}

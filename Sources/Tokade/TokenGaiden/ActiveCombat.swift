import Foundation

/// State of an in-progress encounter. The TokegotchiState carries one of
/// these when `combatMode == .active` and an encounter has been triggered
/// but not resolved. Players step through it with Attack / Item / Run.
struct ActiveBattle: Codable, Equatable {
    var monsterName: String
    var monsterMaxHP: Int
    var monsterHP: Int
    var monsterAttack: Int
    var monsterDefense: Int
    var monsterExpReward: Int
    var monsterGoldReward: Int
    /// Most recent battle line ("You strike for 12.", "It hits back for 4.")
    var log: [String]
    /// True once the player has clicked Attack at least once — used to
    /// prevent an instant-flee free win on encounter spawn.
    var actionTaken: Bool
    /// Set when the fight has ended but the outcome dialog hasn't been
    /// dismissed yet. Player must press Continue to clear it.
    var resolvedOutcome: ResolvedOutcome?

    enum ResolvedOutcome: String, Codable, Equatable {
        case victory, fled, playerDown
    }

    init(encounter: Encounter) {
        monsterName       = encounter.monsterName
        monsterMaxHP      = encounter.hp
        monsterHP         = encounter.hp
        monsterAttack     = encounter.attack
        monsterDefense    = encounter.defense
        monsterExpReward  = encounter.expReward
        monsterGoldReward = encounter.goldReward
        log               = ["A wild \(encounter.monsterName) appeared!"]
        actionTaken       = false
        resolvedOutcome   = nil
    }
}

/// Outcome of a single combat round.
enum CombatRoundResult: Equatable {
    case ongoing
    case victory(exp: Int, gold: Int)
    case fled
    case playerDown   // pet HP hit 0 mid-fight; defers to TickProcessor critical
}

/// Pure-functional combat math. Each method takes the current state +
/// battle, applies the action, returns the updated state + battle (which
/// may be `nil` if the fight is over) + the round result.
enum CombatEngine {
    /// Player attacks once. Monster counter-attacks if it survives.
    static func attack(
        state: TokegotchiState,
        battle: ActiveBattle
    ) -> (TokegotchiState, ActiveBattle?, CombatRoundResult) {
        var s = state
        var b = battle
        b.actionTaken = true
        let eff = s.effectiveStats
        let playerAttack = max(1, eff.str + eff.dex / 2 + s.gearAttackBonus)
        let damage = max(1, playerAttack - b.monsterDefense)
        b.monsterHP -= damage
        b.log.append("You strike \(b.monsterName) for \(damage).")
        if b.monsterHP <= 0 {
            s.progress.exp += b.monsterExpReward
            s.progress.gold += b.monsterGoldReward
            b.log.append("Defeated! +\(b.monsterExpReward) EXP, +\(b.monsterGoldReward)g.")
            return (s, b, .victory(exp: b.monsterExpReward, gold: b.monsterGoldReward))
        }
        // Monster counterattacks. Player DEX/2 + gear DEF acts as defense.
        let playerDef = eff.dex / 2 + s.gearDefenseBonus
        let mDamage = max(1, b.monsterAttack - playerDef)
        s.vitals.hp = max(0, s.vitals.hp - mDamage)
        b.log.append("\(b.monsterName) hits back for \(mDamage).")
        if s.vitals.hp <= 0 {
            b.log.append("You're knocked out!")
            return (s, b, .playerDown)
        }
        return (s, b, .ongoing)
    }

    /// Player uses an item mid-combat. Item heals or buffs, then the monster
    /// counter-attacks. Only food items consume a turn currently.
    static func useItem(
        _ itemId: String,
        state: TokegotchiState,
        battle: ActiveBattle
    ) -> (TokegotchiState, ActiveBattle?, CombatRoundResult) {
        var s = state
        var b = battle
        b.actionTaken = true
        let (afterUse, result) = ItemUsage.use(itemId, state: s)
        s = afterUse
        switch result {
        case let .healed(hp):
            b.log.append("You ate \(ItemCatalog.label(itemId)) — +\(hp) HP.")
        case let .restoredSP(sp):
            b.log.append("Drank \(ItemCatalog.label(itemId)) — +\(sp) SP.")
        case .missing, .unknown:
            b.log.append("Nothing happened.")
            return (s, b, .ongoing)
        default:
            b.log.append("Used \(ItemCatalog.label(itemId)).")
        }
        // Monster gets a free hit while we feed.
        let playerDef = s.effectiveStats.dex / 2 + s.gearDefenseBonus
        let mDamage = max(1, b.monsterAttack - playerDef)
        s.vitals.hp = max(0, s.vitals.hp - mDamage)
        b.log.append("\(b.monsterName) lashes out for \(mDamage).")
        if s.vitals.hp <= 0 {
            b.log.append("You're knocked out!")
            return (s, b, .playerDown)
        }
        return (s, b, .ongoing)
    }

    /// Player attempts to flee. Success chance scales with AGI vs monster
    /// attack. Failure means losing a free attack from the monster.
    static func flee(
        state: TokegotchiState,
        battle: ActiveBattle
    ) -> (TokegotchiState, ActiveBattle?, CombatRoundResult) {
        var s = state
        var b = battle
        b.actionTaken = true
        let eff = s.effectiveStats
        let chance = min(95, 40 + eff.agi * 4)
        let roll = Int.random(in: 1...100)
        if roll <= chance {
            b.log.append("You slip away from \(b.monsterName).")
            return (s, b, .fled)
        }
        let mDamage = max(1, b.monsterAttack - eff.dex / 2 - s.gearDefenseBonus)
        s.vitals.hp = max(0, s.vitals.hp - mDamage)
        b.log.append("Couldn't escape! \(b.monsterName) hits for \(mDamage).")
        if s.vitals.hp <= 0 {
            b.log.append("You're knocked out!")
            return (s, b, .playerDown)
        }
        return (s, b, .ongoing)
    }
}

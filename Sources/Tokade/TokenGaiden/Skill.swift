import Foundation

/// One combat skill a Tokegotchi can learn. Skills cost SP to use mid-fight
/// and scale with one of the player's stats. Learned via trainer NPCs.
struct Skill: Hashable, Identifiable {
    let id: String
    let name: String
    let glyph: String
    let description: String
    let spCost: Int
    let effect: Effect

    /// What pressing this skill button in combat does.
    enum Effect: Hashable {
        /// Damage = `base + stat × multiplier`. Scaling stat indicates the
        /// dependent attribute for tooltips.
        case damage(base: Int, scalingStat: String, multiplier: Double)
        /// Heal the pet by `base + stat × multiplier` HP.
        case heal(base: Int, scalingStat: String, multiplier: Double)
        /// Reduce next monster hit by half. Lasts the current battle only.
        case block
        /// Guaranteed flee.
        case escape
        /// Inflicts a temporary debuff: reduce monster attack by N for the
        /// rest of the battle.
        case weaken(by: Int)
    }
}

enum SkillCatalog {
    static let all: [Skill] = [
        Skill(id: "strike",      name: "Power Strike", glyph: "💥",
              description: "Heavy attack scaling with STR.",
              spCost: 5,
              effect: .damage(base: 4, scalingStat: "STR", multiplier: 1.8)),
        Skill(id: "pierce",      name: "Pierce", glyph: "🗡️",
              description: "Precise attack scaling with DEX.",
              spCost: 5,
              effect: .damage(base: 4, scalingStat: "DEX", multiplier: 1.8)),
        Skill(id: "fireball",    name: "Fireball", glyph: "🔥",
              description: "Cast fire scaling with INT.",
              spCost: 12,
              effect: .damage(base: 10, scalingStat: "INT", multiplier: 2.5)),
        Skill(id: "inspire",     name: "Inspire-Attack", glyph: "📣",
              description: "Charm-fueled strike scaling with CHA.",
              spCost: 8,
              effect: .damage(base: 6, scalingStat: "CHA", multiplier: 2.0)),
        Skill(id: "mend",        name: "Mend", glyph: "❤️‍🩹",
              description: "Restore HP scaling with CHA.",
              spCost: 10,
              effect: .heal(base: 15, scalingStat: "CHA", multiplier: 2.0)),
        Skill(id: "greater-heal", name: "Greater Heal", glyph: "✨",
              description: "Restore lots of HP scaling with CHA.",
              spCost: 25,
              effect: .heal(base: 30, scalingStat: "CHA", multiplier: 3.5)),
        Skill(id: "block",       name: "Block", glyph: "🛡️",
              description: "Brace — the next monster hit deals half damage.",
              spCost: 4,
              effect: .block),
        Skill(id: "escape",      name: "Escape", glyph: "💨",
              description: "Guaranteed flee from the current encounter.",
              spCost: 8,
              effect: .escape),
        Skill(id: "weaken",      name: "Weaken", glyph: "🌀",
              description: "Reduce monster attack for the rest of the fight.",
              spCost: 6,
              effect: .weaken(by: 3)),
    ]

    static let byId: [String: Skill] = {
        var d: [String: Skill] = [:]
        for s in all { d[s.id] = s }
        return d
    }()

    static func find(_ id: String) -> Skill? {
        byId[id]
    }
}

/// Compute the immediate effect of a skill against the player + current
/// battle. Pure-functional like the rest of CombatEngine. Returns the
/// updated state, updated battle (nil if fight ended), and the round
/// result.
enum SkillResolution {
    static func cast(
        _ skill: Skill,
        state: TokegotchiState,
        battle: ActiveBattle
    ) -> (TokegotchiState, ActiveBattle?, CombatRoundResult) {
        guard state.vitals.sp >= skill.spCost else {
            var b = battle
            b.log.append("Not enough SP for \(skill.name).")
            return (state, b, .ongoing)
        }
        var s = state
        var b = battle
        b.actionTaken = true
        s.vitals.sp -= skill.spCost

        switch skill.effect {
        case let .damage(base, stat, mult):
            let v = statValue(stat, s.vitals.stats)
            let raw = Double(base) + Double(v) * mult
            let damage = max(1, Int(raw) - b.monsterDefense)
            b.monsterHP -= damage
            b.log.append("Cast \(skill.name) — \(damage) damage.")
            if b.monsterHP <= 0 {
                s.progress.exp += b.monsterExpReward
                s.progress.gold += b.monsterGoldReward
                b.log.append("Defeated! +\(b.monsterExpReward) EXP, +\(b.monsterGoldReward)g.")
                return (s, b, .victory(exp: b.monsterExpReward, gold: b.monsterGoldReward))
            }
        case let .heal(base, stat, mult):
            let v = statValue(stat, s.vitals.stats)
            let raw = Double(base) + Double(v) * mult
            let before = s.vitals.hp
            s.vitals.hp = min(s.vitals.hpMax, before + Int(raw))
            let restored = s.vitals.hp - before
            b.log.append("Cast \(skill.name) — +\(restored) HP.")
        case .block:
            // Halve next monster attack by reducing it to half on next turn.
            // We model it by shaving the current `monsterAttack` for the
            // remainder of the fight (simpler than tracking a buff queue).
            b.monsterAttack = max(1, b.monsterAttack / 2)
            b.log.append("You brace — \(b.monsterName)'s attack lessens.")
        case .escape:
            b.log.append("You vanish in a puff of smoke!")
            return (s, b, .fled)
        case let .weaken(by):
            b.monsterAttack = max(1, b.monsterAttack - by)
            b.log.append("\(b.monsterName) is weakened (-\(by) ATK).")
        }

        // Monster counterattacks if it's still standing.
        let playerDef = s.vitals.stats.dex / 2
        let mDamage = max(1, b.monsterAttack - playerDef)
        s.vitals.hp = max(0, s.vitals.hp - mDamage)
        b.log.append("\(b.monsterName) hits for \(mDamage).")
        if s.vitals.hp <= 0 {
            b.log.append("You're knocked out!")
            return (s, b, .playerDown)
        }
        return (s, b, .ongoing)
    }

    private static func statValue(_ name: String, _ stats: TokegotchiState.Stats) -> Int {
        switch name {
        case "STR": return stats.str
        case "DEX": return stats.dex
        case "INT": return stats.int
        case "AGI": return stats.agi
        case "CHA": return stats.cha
        default:    return 0
        }
    }
}

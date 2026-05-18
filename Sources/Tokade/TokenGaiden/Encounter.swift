import Foundation

/// A monster encounter, derived from the current region's flavor at trigger
/// time. v1 resolves all encounters passively — `Encounter.resolve` does the
/// math against the player's stats and returns rewards. Active turn-based
/// modal is queued for a follow-up PR.
struct Encounter: Equatable {
    let monsterName: String
    let hp: Int
    let attack: Int
    let defense: Int
    let expReward: Int
    let goldReward: Int
}

extension Region.Flavor {
    /// Roster of monsters for this flavor. Tuned to feel like proper JRPG
    /// fights — multiple rounds, real damage on the player, gear/strategy
    /// matters. Numbers are rough and scale gently across the flavor's
    /// difficulty band.
    var monsters: [Encounter] {
        switch self {
        case .stonework:
            return [
                Encounter(monsterName: "Loose Brick",     hp: 32,  attack: 7,  defense: 3,  expReward: 8,  goldReward: 5),
                Encounter(monsterName: "Mortar Mite",     hp: 26,  attack: 9,  defense: 2,  expReward: 9,  goldReward: 6),
                Encounter(monsterName: "Quarry Bat",      hp: 38,  attack: 10, defense: 3,  expReward: 14, goldReward: 8),
                Encounter(monsterName: "Stone Gargoyle",  hp: 64,  attack: 12, defense: 7,  expReward: 22, goldReward: 14),
                Encounter(monsterName: "Granite Golem",   hp: 90,  attack: 14, defense: 10, expReward: 30, goldReward: 20),
            ]
        case .ironFortress:
            return [
                Encounter(monsterName: "Rust Imp",        hp: 36,  attack: 11, defense: 4,  expReward: 12, goldReward: 8),
                Encounter(monsterName: "Bolt Crab",       hp: 30,  attack: 9,  defense: 6,  expReward: 11, goldReward: 7),
                Encounter(monsterName: "Compile Beetle",  hp: 52,  attack: 10, defense: 7,  expReward: 18, goldReward: 12),
                Encounter(monsterName: "Furnace Wraith",  hp: 60,  attack: 16, defense: 5,  expReward: 24, goldReward: 14),
                Encounter(monsterName: "Iron Sentinel",   hp: 100, attack: 17, defense: 12, expReward: 38, goldReward: 22),
            ]
        case .gardenVillage:
            return [
                Encounter(monsterName: "Pollen Wisp",     hp: 22,  attack: 6,  defense: 1,  expReward: 6,  goldReward: 4),
                Encounter(monsterName: "Mushroom Sprite", hp: 30,  attack: 8,  defense: 3,  expReward: 10, goldReward: 6),
                Encounter(monsterName: "Vine Snare",      hp: 44,  attack: 10, defense: 4,  expReward: 14, goldReward: 8),
                Encounter(monsterName: "Snail Sage",      hp: 38,  attack: 7,  defense: 9,  expReward: 14, goldReward: 9),
                Encounter(monsterName: "Garden Snake",    hp: 56,  attack: 13, defense: 5,  expReward: 22, goldReward: 12),
            ]
        case .bazaar:
            return [
                Encounter(monsterName: "Pickpocket",      hp: 28,  attack: 9,  defense: 3,  expReward: 8,  goldReward: 16),
                Encounter(monsterName: "Hawker",          hp: 34,  attack: 8,  defense: 5,  expReward: 11, goldReward: 12),
                Encounter(monsterName: "Cutpurse",        hp: 40,  attack: 12, defense: 4,  expReward: 14, goldReward: 18),
                Encounter(monsterName: "Charlatan",       hp: 46,  attack: 11, defense: 6,  expReward: 18, goldReward: 22),
                Encounter(monsterName: "Backstreet Brawler", hp: 72, attack: 16, defense: 8, expReward: 28, goldReward: 26),
            ]
        case .openSteppe:
            return [
                Encounter(monsterName: "Steppe Hare",     hp: 18,  attack: 6,  defense: 1,  expReward: 5,  goldReward: 4),
                Encounter(monsterName: "Wind Wisp",       hp: 22,  attack: 9,  defense: 0,  expReward: 8,  goldReward: 5),
                Encounter(monsterName: "Plains Mantis",   hp: 40,  attack: 12, defense: 3,  expReward: 14, goldReward: 8),
                Encounter(monsterName: "Steppe Wolf",     hp: 48,  attack: 14, defense: 3,  expReward: 18, goldReward: 10),
                Encounter(monsterName: "Sun Hawk",        hp: 60,  attack: 16, defense: 4,  expReward: 24, goldReward: 14),
            ]
        case .wilderness:
            return [
                Encounter(monsterName: "Stray Slime",     hp: 16,  attack: 4,  defense: 1,  expReward: 4,  goldReward: 3),
                Encounter(monsterName: "Lost Sprite",     hp: 22,  attack: 6,  defense: 2,  expReward: 7,  goldReward: 5),
                Encounter(monsterName: "Cave Bat",        hp: 26,  attack: 8,  defense: 2,  expReward: 9,  goldReward: 5),
                Encounter(monsterName: "Goblin Scout",    hp: 36,  attack: 10, defense: 3,  expReward: 13, goldReward: 8),
                Encounter(monsterName: "Forgotten Knight",hp: 70,  attack: 14, defense: 8,  expReward: 26, goldReward: 16),
            ]
        }
    }
}

/// Difficulty tiers for dungeon runs vs random encounters.
enum EncounterTier {
    case random        // any beatable monster, salt-rotates
    case dungeon       // highest-reward monster in the roster — boss-flavored
}

enum EncounterEngine {
    /// Outcome of a passive auto-resolve. The encounter card surfaces this.
    enum Outcome: Equatable {
        case victory(expGained: Int, goldGained: Int)
        case fled
    }

    /// Resolve a fight against `m` deterministically against the player's
    /// stats. The fight is modeled as exchanging blows: the player kills the
    /// monster in N turns, taking damage on each of the first N-1 of those
    /// (the monster doesn't get a swing on the killing blow).
    /// - On victory: apply EXP + gold and subtract the HP lost during the fight.
    /// - On flee (too many turns to kill): take a single parting hit and bail.
    static func resolve(_ m: Encounter, against state: TokegotchiState) -> (TokegotchiState, Outcome) {
        let eff = state.effectiveStats
        let playerAttack = max(1, eff.str + eff.dex / 2 + state.gearAttackBonus)
        let damagePerSwing = max(1, playerAttack - m.defense)
        let turnsToKill = (m.hp + damagePerSwing - 1) / damagePerSwing
        let playerDef = eff.dex / 2 + state.gearDefenseBonus
        let damageTaken = max(1, m.attack - playerDef)
        var s = state
        if turnsToKill > 6 {
            // Honorable flee: still scuffed up by the encounter.
            s.vitals.hp = max(0, s.vitals.hp - damageTaken)
            return (s, .fled)
        }
        // Monster swings on (turnsToKill - 1) rounds — it dies on its own turn.
        let totalDamage = damageTaken * max(0, turnsToKill - 1)
        s.vitals.hp = max(0, s.vitals.hp - totalDamage)
        s.progress.exp += m.expReward
        s.progress.gold += m.goldReward
        return (s, .victory(expGained: m.expReward, goldGained: m.goldReward))
    }

    /// Pick the encounter to trigger for the current region given the player's
    /// strength. Deterministic given (region, ageTokens) — same player + same
    /// region cycles through monsters predictably.
    ///
    /// Picks among monsters the player can still beat in a reasonable number
    /// of turns. If none are beatable, returns the weakest monster (an
    /// honorable flee).
    static func choose(
        for flavor: Region.Flavor,
        playerStats: TokegotchiState.Stats,
        salt: Int,
        tier: EncounterTier = .random
    ) -> Encounter? {
        let roster = flavor.monsters
        guard !roster.isEmpty else { return nil }
        switch tier {
        case .random:
            let attack = max(1, playerStats.str + playerStats.dex / 2)
            // Allow up to 6 swings to feel like a real fight, not a chip race.
            let beatable = roster.filter { m in
                let damage = max(1, attack - m.defense)
                return (m.hp + damage - 1) / damage <= 6
            }
            if beatable.isEmpty { return roster.min(by: { $0.expReward < $1.expReward }) }
            return beatable[salt % beatable.count]
        case .dungeon:
            // Picks the highest-reward monster regardless of whether it's
            // beatable — playing the dungeon is the player taking the risk.
            // Slightly buff its stats so dungeon monsters are tougher than
            // the random-roll equivalent.
            guard let base = roster.max(by: { $0.expReward < $1.expReward }) else { return nil }
            return Encounter(
                monsterName: base.monsterName,
                hp: base.hp + base.hp / 3,
                attack: base.attack + 2,
                defense: base.defense + 2,
                expReward: base.expReward + base.expReward / 2,
                goldReward: base.goldReward + base.goldReward / 2
            )
        }
    }
}

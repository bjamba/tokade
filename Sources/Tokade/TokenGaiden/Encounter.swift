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
    /// Roster of monsters for this flavor. v1 has 1–3 per flavor.
    var monsters: [Encounter] {
        switch self {
        case .stonework:
            return [
                Encounter(monsterName: "Granite Golem",  hp: 30, attack: 6,  defense: 4, expReward: 12, goldReward: 8),
                Encounter(monsterName: "Loose Brick",    hp: 12, attack: 3,  defense: 1, expReward: 4,  goldReward: 3),
            ]
        case .ironFortress:
            return [
                Encounter(monsterName: "Rust Imp",       hp: 18, attack: 5,  defense: 2, expReward: 6,  goldReward: 5),
                Encounter(monsterName: "Compile Beetle", hp: 24, attack: 4,  defense: 3, expReward: 10, goldReward: 7),
                Encounter(monsterName: "Iron Sentinel",  hp: 40, attack: 8,  defense: 6, expReward: 18, goldReward: 12),
            ]
        case .gardenVillage:
            return [
                Encounter(monsterName: "Vine Snare",     hp: 22, attack: 5,  defense: 2, expReward: 8,  goldReward: 5),
                Encounter(monsterName: "Snail Sage",     hp: 15, attack: 3,  defense: 5, expReward: 7,  goldReward: 4),
            ]
        case .bazaar:
            return [
                Encounter(monsterName: "Pickpocket",     hp: 14, attack: 4,  defense: 2, expReward: 5,  goldReward: 10),
                Encounter(monsterName: "Hawker",         hp: 18, attack: 3,  defense: 3, expReward: 6,  goldReward: 7),
            ]
        case .openSteppe:
            return [
                Encounter(monsterName: "Steppe Wolf",    hp: 20, attack: 7,  defense: 1, expReward: 9,  goldReward: 4),
                Encounter(monsterName: "Wind Wisp",      hp: 10, attack: 5,  defense: 0, expReward: 4,  goldReward: 3),
            ]
        case .wilderness:
            return [
                Encounter(monsterName: "Stray Slime",    hp: 8,  attack: 2,  defense: 0, expReward: 2,  goldReward: 2),
                Encounter(monsterName: "Lost Sprite",    hp: 12, attack: 3,  defense: 1, expReward: 4,  goldReward: 3),
            ]
        }
    }
}

enum EncounterEngine {
    /// Outcome of a passive auto-resolve. The encounter card surfaces this.
    enum Outcome: Equatable {
        case victory(expGained: Int, goldGained: Int)
        case fled
    }

    /// Resolve a fight against `m` deterministically against the player's
    /// stats. v1 algorithm:
    /// - Player ATK = STR + DEX/2
    /// - Player DEF = DEX/2
    /// - Compare ATK to monster HP; if it would take more than 6 player-turns
    ///   to win, the player flees instead.
    /// - On victory, apply EXP + gold; bypass any HP loss (passive mode is
    ///   forgiving by design).
    static func resolve(_ m: Encounter, against state: TokegotchiState) -> (TokegotchiState, Outcome) {
        let stats = state.vitals.stats
        let playerAttack = max(1, stats.str + stats.dex / 2)
        let turnsToKill = (m.hp + playerAttack - 1) / playerAttack
        var s = state
        if turnsToKill > 6 {
            return (s, .fled)
        }
        s.progress.exp += m.expReward
        s.progress.gold += m.goldReward
        return (s, .victory(expGained: m.expReward, goldGained: m.goldReward))
    }

    /// Pick the encounter to trigger for the current region given the player's
    /// strength. Deterministic given (region, ageTokens) — same player + same
    /// region cycles through monsters predictably.
    ///
    /// Picks the "highest" monster (by expReward) the player can still beat.
    /// If none are beatable, returns the weakest monster (an honorable flee).
    static func choose(
        for flavor: Region.Flavor,
        playerStats: TokegotchiState.Stats,
        salt: Int
    ) -> Encounter? {
        let roster = flavor.monsters
        guard !roster.isEmpty else { return nil }
        let attack = max(1, playerStats.str + playerStats.dex / 2)
        let beatable = roster.filter { ($0.hp + attack - 1) / attack <= 6 }
        if beatable.isEmpty { return roster.min(by: { $0.expReward < $1.expReward }) }
        return beatable[salt % beatable.count]
    }
}

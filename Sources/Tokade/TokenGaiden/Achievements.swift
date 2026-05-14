import Foundation

/// An auto-detected milestone that fires once. Persisted in the Tokegotchi
/// inventory under a reserved key so re-launches don't re-fire them.
struct Achievement: Equatable {
    let id: String
    let title: String
    let description: String

    /// Predicate evaluated after each tick — returns true once the milestone
    /// is reached. Pure function over state.
    let predicate: (TokegotchiState, TokegotchiState.Stats) -> Bool

    static func == (lhs: Achievement, rhs: Achievement) -> Bool {
        lhs.id == rhs.id
    }
}

enum AchievementCatalog {
    /// Reserved inventory key holding earned-achievement ids one per "slot".
    /// We store them as items (count = 1) so the existing save format covers
    /// them without a schema bump.
    static let inventoryPrefix = "achievement:"

    static let all: [Achievement] = [
        Achievement(
            id: "first-light",
            title: "First Light",
            description: "Hatched your first Tokegotchi.",
            predicate: { _, _ in true }                  // fires on any state
        ),
        Achievement(
            id: "first-million",
            title: "First Million",
            description: "Earned a million age tokens.",
            predicate: { s, _ in s.identity.ageTokens >= 1_000_000 }
        ),
        Achievement(
            id: "strong-start",
            title: "Strong Start",
            description: "Reached STR 10.",
            predicate: { _, stats in stats.str >= 10 }
        ),
        Achievement(
            id: "deft-hands",
            title: "Deft Hands",
            description: "Reached DEX 10.",
            predicate: { _, stats in stats.dex >= 10 }
        ),
        Achievement(
            id: "well-read",
            title: "Well Read",
            description: "Reached INT 10.",
            predicate: { _, stats in stats.int >= 10 }
        ),
        Achievement(
            id: "swift-foot",
            title: "Swift Foot",
            description: "Reached AGI 10.",
            predicate: { _, stats in stats.agi >= 10 }
        ),
        Achievement(
            id: "well-spoken",
            title: "Well Spoken",
            description: "Reached CHA 10.",
            predicate: { _, stats in stats.cha >= 10 }
        ),
        Achievement(
            id: "first-shopkeeper",
            title: "First Pocket",
            description: "Earned 100 gold.",
            predicate: { s, _ in s.progress.gold >= 100 }
        ),
        Achievement(
            id: "frequent-flyer",
            title: "Frequent Flyer",
            description: "Visited 3 distinct regions.",
            predicate: { s, _ in s.world.reputation.count >= 3 }
        ),
        Achievement(
            id: "well-known",
            title: "Well Known",
            description: "Reputation 50 in any region.",
            predicate: { s, _ in (s.world.reputation.values.max() ?? 0) >= 50 }
        ),
        Achievement(
            id: "elder-status",
            title: "Elder Status",
            description: "Survived to 70% of lifespan.",
            predicate: { s, _ in
                let pct = Double(s.identity.ageTokens) / Double(max(s.identity.lifespanTokens, 1))
                return pct >= 0.7
            }
        ),
    ]

    static let byId: [String: Achievement] = {
        var d: [String: Achievement] = [:]
        for a in all { d[a.id] = a }
        return d
    }()

    /// Run the catalog over a state; return achievement ids that just became
    /// earned (not already in the inventory).
    static func newlyEarned(in state: TokegotchiState) -> [String] {
        all.compactMap { ach in
            let key = inventoryPrefix + ach.id
            let already = state.inventory.items[key] ?? 0
            if already > 0 { return nil }
            return ach.predicate(state, state.vitals.stats) ? ach.id : nil
        }
    }
}

import Foundation

/// Pure-functional NPC interactions. Both shops and trainers are modeled as
/// "spend resource → mutate state" with explicit success/failure results.
enum NPCInteraction {
    enum BuyResult: Equatable {
        case bought(itemId: String, price: Int)
        case insufficientGold
        case unknownItem
        case reputationLow      // future: rep-gated stock
    }

    enum TrainResult: Equatable {
        case trained(label: String, costExp: Int)
        case insufficientExp
        case alreadyLearned
        case unknownOffering
    }

    /// Attempt to buy `offer` from the player's gold. Returns updated state.
    /// `priceOverride` lets stat-check skill flavors apply a discount (e.g.
    /// haggle with CHA).
    static func buy(_ offer: ShopOffer, state: TokegotchiState, priceOverride: Int? = nil) -> (TokegotchiState, BuyResult) {
        guard ItemCatalog.find(offer.itemId) != nil else { return (state, .unknownItem) }
        let price = priceOverride ?? offer.priceGold
        guard state.progress.gold >= price else { return (state, .insufficientGold) }
        var s = state
        s.progress.gold -= price
        s.inventory.items[offer.itemId, default: 0] += 1
        return (s, .bought(itemId: offer.itemId, price: price))
    }

    /// Discount percentage given a CHA value. 0–24%. Tuned so a fresh pet
    /// gets some discount and a maxed-CHA pet saves a chunk.
    static func haggleDiscount(cha: Int) -> Double {
        // 1% per CHA point, capped at 24%. Pets with CHA = 0 get nothing.
        let pct = Double(min(max(cha, 0), 24))
        return pct / 100.0
    }

    static func haggledPrice(_ offer: ShopOffer, cha: Int) -> Int {
        let d = haggleDiscount(cha: cha)
        return max(1, Int(Double(offer.priceGold) * (1.0 - d)))
    }

    /// Attempt to spend EXP on a trainer offering. v1 only supports
    /// stat-boost offerings — once consumed, the offering is permanent.
    static func train(_ offering: TrainerOffering, state: TokegotchiState) -> (TokegotchiState, TrainResult) {
        // Skill grants are one-shot: re-training a learned skill used to
        // silently consume EXP for nothing. Fail loudly so the caller can
        // disable the button.
        if case let .learnSkill(skillId) = offering.effect,
           state.inventory.skillsLearned.contains(skillId) {
            return (state, .alreadyLearned)
        }
        guard state.progress.exp >= offering.priceExp else { return (state, .insufficientExp) }
        var s = state
        s.progress.exp -= offering.priceExp
        switch offering.effect {
        case let .statBoost(stat, delta):
            switch stat {
            case "STR": s.vitals.stats.str += delta
            case "DEX": s.vitals.stats.dex += delta
            case "INT": s.vitals.stats.int += delta
            case "AGI": s.vitals.stats.agi += delta
            case "CHA": s.vitals.stats.cha += delta
            default:    return (state, .unknownOffering)
            }
        case let .healMax(by):
            // Adds a virtual buff by raising both STR and DEX equally (since
            // hpMax = 80 + (STR+DEX)*2). Slightly hacky but keeps everything
            // expressed in the same data model.
            let halfBoost = by / 4
            s.vitals.stats.str += halfBoost
            s.vitals.stats.dex += halfBoost
        case let .learnSkill(skillId):
            guard SkillCatalog.find(skillId) != nil else { return (state, .unknownOffering) }
            s.inventory.skillsLearned.append(skillId)
        }
        return (s, .trained(label: offering.label, costExp: offering.priceExp))
    }
}

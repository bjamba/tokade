import Foundation

/// One usable item the player can spend on the pet. Item identity is the
/// stable string id (e.g. `"hearty-meat"`); display data is derived.
struct ItemDef: Equatable {
    let id: String
    let display: String
    let glyph: String
    let kind: Kind

    enum Kind: Equatable {
        case food(hp: Int)
        case spPotion(sp: Int)
        case statBoost(stat: String, delta: Int)
        case scrap(sellGold: Int)
        case keyItem
    }
}

/// Static catalog of every item known to v1. Lookup is by id — items not in
/// the catalog still appear in the inventory but can't be used.
enum ItemCatalog {
    static let all: [ItemDef] = [
        // Food (HP recovery)
        ItemDef(id: "bread",        display: "Bread",        glyph: "🍞", kind: .food(hp: 5)),
        ItemDef(id: "hearty-meat",  display: "Hearty meat",  glyph: "🍖", kind: .food(hp: 25)),
        ItemDef(id: "feast",        display: "Feast",        glyph: "🍱", kind: .food(hp: 75)),

        // SP potions
        ItemDef(id: "small-sp-potion",  display: "Small SP potion",  glyph: "🧪", kind: .spPotion(sp: 20)),
        ItemDef(id: "medium-sp-potion", display: "Medium SP potion", glyph: "🧪", kind: .spPotion(sp: 50)),

        // Stat-boost items (consumed for permanent stat bump)
        ItemDef(id: "dumbbell", display: "Dumbbell", glyph: "🏋",  kind: .statBoost(stat: "STR", delta: 1)),
        ItemDef(id: "chisel",   display: "Chisel",   glyph: "🔨",  kind: .statBoost(stat: "DEX", delta: 1)),
        ItemDef(id: "scroll",   display: "Scroll",   glyph: "📜",  kind: .statBoost(stat: "INT", delta: 1)),
        ItemDef(id: "boots",    display: "Boots",    glyph: "👢",  kind: .statBoost(stat: "AGI", delta: 1)),
        ItemDef(id: "banner",   display: "Banner",   glyph: "🚩",  kind: .statBoost(stat: "CHA", delta: 1)),

        // Misc
        ItemDef(id: "scrap", display: "Scrap", glyph: "🪨", kind: .scrap(sellGold: 2)),
    ]

    static let byId: [String: ItemDef] = {
        var d: [String: ItemDef] = [:]
        for item in all { d[item.id] = item }
        return d
    }()

    static func find(_ id: String) -> ItemDef? {
        byId[id]
    }

    /// User-facing label including glyph for in-game lists.
    static func label(_ id: String) -> String {
        if let def = byId[id] { return "\(def.glyph) \(def.display)" }
        return id
    }
}

/// Result of using one item. Pure-functional: pass current state in, get
/// updated state + an observable effect out.
enum ItemUsage {
    enum Result: Equatable {
        case healed(hp: Int)
        case restoredSP(sp: Int)
        case statRaised(stat: String, delta: Int)
        case sold(gold: Int)
        case missing
        case unknown
    }

    /// Apply one use of `id` against `state`. Decrements the item count.
    /// Returns the updated state and a Result describing what happened.
    static func use(_ id: String, state: TokegotchiState) -> (TokegotchiState, Result) {
        guard let def = ItemCatalog.find(id) else { return (state, .unknown) }
        let count = state.inventory.items[id] ?? 0
        guard count > 0 else { return (state, .missing) }
        var s = state
        // Decrement first; missing-key delete keeps the inventory clean.
        if count <= 1 {
            s.inventory.items.removeValue(forKey: id)
        } else {
            s.inventory.items[id] = count - 1
        }
        switch def.kind {
        case let .food(hp):
            let before = s.vitals.hp
            s.vitals.hp = min(s.vitals.hpMax, before + hp)
            return (s, .healed(hp: s.vitals.hp - before))
        case let .spPotion(sp):
            let before = s.vitals.sp
            s.vitals.sp = min(s.vitals.spMax, before + sp)
            return (s, .restoredSP(sp: s.vitals.sp - before))
        case let .statBoost(stat, delta):
            switch stat {
            case "STR": s.vitals.stats.str += delta
            case "DEX": s.vitals.stats.dex += delta
            case "INT": s.vitals.stats.int += delta
            case "AGI": s.vitals.stats.agi += delta
            case "CHA": s.vitals.stats.cha += delta
            default:    break
            }
            return (s, .statRaised(stat: stat, delta: delta))
        case let .scrap(sellGold):
            s.progress.gold += sellGold
            return (s, .sold(gold: sellGold))
        case .keyItem:
            // Re-add the item; key items aren't consumable by the use button.
            s.inventory.items[id] = count
            return (s, .unknown)
        }
    }
}

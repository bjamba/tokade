import Foundation

/// Stat-bearing equipment separate from cosmetic items. One piece per slot
/// can be equipped at a time. Slots: weapon, armor, amulet, ring.
struct Gear: Hashable, Identifiable {
    let id: String
    let name: String
    let glyph: String
    let slot: Slot
    let description: String
    /// Effects compose additively on top of the player's base stats.
    let statBonus: TokegotchiState.Stats
    /// Direct attack bonus added to player ATK calculation.
    let attackBonus: Int
    /// Direct defense bonus added to player DEF calculation.
    let defenseBonus: Int
    /// Purchase price if found in a shop (also approximate trade value).
    let priceGold: Int

    enum Slot: String, CaseIterable, Codable {
        case weapon
        case armor
        case amulet
        case ring
    }
}

enum GearCatalog {
    static let all: [Gear] = [
        // Weapons
        Gear(id: "rusty-dagger", name: "Rusty Dagger", glyph: "🗡", slot: .weapon,
             description: "Battered but sharp.",
             statBonus: TokegotchiState.Stats(str: 0, dex: 1, int: 0, agi: 0, cha: 0),
             attackBonus: 2, defenseBonus: 0, priceGold: 30),
        Gear(id: "iron-sword", name: "Iron Sword", glyph: "⚔️", slot: .weapon,
             description: "Standard issue.",
             statBonus: TokegotchiState.Stats(str: 2, dex: 0, int: 0, agi: 0, cha: 0),
             attackBonus: 5, defenseBonus: 0, priceGold: 120),
        Gear(id: "war-hammer", name: "War Hammer", glyph: "🔨", slot: .weapon,
             description: "Heavy. Devastating.",
             statBonus: TokegotchiState.Stats(str: 4, dex: 0, int: 0, agi: -1, cha: 0),
             attackBonus: 8, defenseBonus: 0, priceGold: 280),
        Gear(id: "elder-staff", name: "Elder Staff", glyph: "🪄", slot: .weapon,
             description: "Hums with stored magic.",
             statBonus: TokegotchiState.Stats(str: 0, dex: 0, int: 4, agi: 0, cha: 1),
             attackBonus: 3, defenseBonus: 1, priceGold: 220),

        // Armor
        Gear(id: "cloth-tunic", name: "Cloth Tunic", glyph: "👕", slot: .armor,
             description: "Better than nothing.",
             statBonus: TokegotchiState.Stats(str: 0, dex: 0, int: 0, agi: 1, cha: 0),
             attackBonus: 0, defenseBonus: 2, priceGold: 25),
        Gear(id: "leather-armor", name: "Leather Armor", glyph: "🥼", slot: .armor,
             description: "Sturdy hide work.",
             statBonus: TokegotchiState.Stats(str: 1, dex: 0, int: 0, agi: 0, cha: 0),
             attackBonus: 0, defenseBonus: 4, priceGold: 90),
        Gear(id: "plate-armor", name: "Plate Armor", glyph: "🛡", slot: .armor,
             description: "Slow but unyielding.",
             statBonus: TokegotchiState.Stats(str: 2, dex: 0, int: 0, agi: -2, cha: 0),
             attackBonus: 0, defenseBonus: 8, priceGold: 260),

        // Amulets
        Gear(id: "wisdom-amulet", name: "Amulet of Wisdom", glyph: "📿", slot: .amulet,
             description: "Warmth at your throat.",
             statBonus: TokegotchiState.Stats(str: 0, dex: 0, int: 3, agi: 0, cha: 2),
             attackBonus: 0, defenseBonus: 1, priceGold: 200),
        Gear(id: "vitality-amulet", name: "Vitality Charm", glyph: "🧿", slot: .amulet,
             description: "Feels like a second heart.",
             statBonus: TokegotchiState.Stats(str: 2, dex: 2, int: 0, agi: 0, cha: 0),
             attackBonus: 0, defenseBonus: 2, priceGold: 240),

        // Rings
        Gear(id: "swift-ring", name: "Swift Ring", glyph: "💍", slot: .ring,
             description: "The world blurs slightly.",
             statBonus: TokegotchiState.Stats(str: 0, dex: 1, int: 0, agi: 3, cha: 0),
             attackBonus: 0, defenseBonus: 1, priceGold: 150),
        Gear(id: "iron-ring", name: "Iron Ring", glyph: "💍", slot: .ring,
             description: "Cold as the forge.",
             statBonus: TokegotchiState.Stats(str: 2, dex: 0, int: 0, agi: 0, cha: 0),
             attackBonus: 1, defenseBonus: 1, priceGold: 110),
        Gear(id: "silver-band", name: "Silver Band", glyph: "💍", slot: .ring,
             description: "Glows under moonlight.",
             statBonus: TokegotchiState.Stats(str: 0, dex: 0, int: 2, agi: 0, cha: 2),
             attackBonus: 0, defenseBonus: 0, priceGold: 160),
    ]

    static let byId: [String: Gear] = {
        var d: [String: Gear] = [:]
        for g in all { d[g.id] = g }
        return d
    }()

    static func find(_ id: String) -> Gear? { byId[id] }

    /// Random gear drop pool for an encounter — picks something appropriate
    /// for the given player strength.
    static func randomDrop(playerATK: Int) -> Gear? {
        let pool = all.filter { ($0.attackBonus + $0.defenseBonus) <= max(2, playerATK / 3 + 2) }
        return pool.randomElement() ?? all.randomElement()
    }
}

/// Effective stats given equipped gear. Returns the base stats plus the sum
/// of `statBonus` from each equipped slot.
extension TokegotchiState {
    /// Stats including gear bonuses.
    var effectiveStats: Stats {
        var s = vitals.stats
        for (_, gid) in inventory.equippedGear where gid != nil {
            guard let id = gid, let g = GearCatalog.find(id) else { continue }
            s.str += g.statBonus.str
            s.dex += g.statBonus.dex
            s.int += g.statBonus.int
            s.agi += g.statBonus.agi
            s.cha += g.statBonus.cha
        }
        return s
    }

    /// Total weapon attack bonus from equipped weapon (+ small bonuses from
    /// other slots like Iron Ring).
    var gearAttackBonus: Int {
        var sum = 0
        for (_, gid) in inventory.equippedGear where gid != nil {
            if let id = gid, let g = GearCatalog.find(id) {
                sum += g.attackBonus
            }
        }
        return sum
    }

    /// Sum of `defenseBonus` from all equipped gear.
    var gearDefenseBonus: Int {
        var sum = 0
        for (_, gid) in inventory.equippedGear where gid != nil {
            if let id = gid, let g = GearCatalog.find(id) {
                sum += g.defenseBonus
            }
        }
        return sum
    }
}

enum GearAction {
    enum EquipResult: Equatable {
        case equipped(slot: String, name: String, replaced: String?)
        case notOwned
        case unknown
    }

    /// Equip a gear item from inventory. If something is already in the slot
    /// it gets returned to inventory (`replaced`).
    static func equip(_ gearId: String, state: TokegotchiState) -> (TokegotchiState, EquipResult) {
        guard let gear = GearCatalog.find(gearId) else { return (state, .unknown) }
        let inv = state.inventory.items[gearId] ?? 0
        guard inv > 0 else { return (state, .notOwned) }
        var s = state
        let slotKey = gear.slot.rawValue
        let replaced = s.inventory.equippedGear[slotKey] ?? nil
        // Return the replaced item to inventory.
        if let r = replaced {
            s.inventory.items[r, default: 0] += 1
        }
        // Take the equipping item out of inventory.
        if inv <= 1 {
            s.inventory.items.removeValue(forKey: gearId)
        } else {
            s.inventory.items[gearId] = inv - 1
        }
        s.inventory.equippedGear[slotKey] = gearId
        return (s, .equipped(slot: slotKey, name: gear.name, replaced: replaced))
    }

    /// Remove a slot's equipped gear and put it back in inventory.
    static func unequip(slot: Gear.Slot, state: TokegotchiState) -> TokegotchiState {
        var s = state
        let key = slot.rawValue
        if let id = s.inventory.equippedGear[key] ?? nil {
            s.inventory.items[id, default: 0] += 1
            s.inventory.equippedGear[key] = nil
        }
        return s
    }
}

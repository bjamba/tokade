import Foundation

/// One cosmetic the player can equip. Identity is the stable string id
/// (e.g. `"sword"`, `"red-cape"`); the matching sprite matrix is bundled
/// under `tg-<slot>-<id>.matrix`. The `unlock` field tells the wardrobe
/// what hint to surface when the player hasn't earned it yet.
struct Cosmetic: Hashable, Identifiable {
    let id: String
    let slot: String          // "hair" / "hat" / "shirt" / "pants" / "belt" / "eyewear" / "cape" / "held"
    let display: String
    let unlock: Unlock

    enum Unlock: Hashable {
        case starter                      // Available from hatch
        case achievement(id: String)      // Granted when achievement fires
        case quest(id: String)            // Granted when quest is claimed
        case drop(rarity: Rarity)         // Random encounter-victory drop

        /// Per-roll weight for cosmetics in the drop pool. 0 for any
        /// non-drop unlock so they're never picked by the drop roller.
        var dropWeight: Double {
            if case let .drop(rarity) = self { return rarity.weight }
            return 0
        }
    }

    enum Rarity: String, Hashable {
        case common, uncommon, rare
        /// Per-victory drop probability for cosmetics with this rarity.
        var weight: Double {
            switch self {
            case .common:   return 0.06   // ~1-in-17 victories
            case .uncommon: return 0.03   // ~1-in-33
            case .rare:     return 0.012  // ~1-in-83
            }
        }
    }
}

/// Static catalog of every cosmetic in the game. Currently mirrors what's
/// baked into `Sources/Tokade/Resources/sprites/` plus design-intent entries
/// for unbaked SVGs (those will render invisibly until baked, but still
/// drop and unlock — they show up in the catalog/hint UI either way).
enum CosmeticCatalog {
    static let all: [Cosmetic] = [
        // ── Hair (already chosen at hatch — every hair is a starter)
        Cosmetic(id: "horns",     slot: "hair", display: "Horns",     unlock: .starter),
        Cosmetic(id: "spiky",     slot: "hair", display: "Spiky",     unlock: .starter),
        Cosmetic(id: "cat-ears",  slot: "hair", display: "Cat ears",  unlock: .starter),
        Cosmetic(id: "pigtails",  slot: "hair", display: "Pigtails",  unlock: .starter),
        Cosmetic(id: "mohawk",    slot: "hair", display: "Mohawk",    unlock: .starter),
        Cosmetic(id: "antennae",  slot: "hair", display: "Antennae",  unlock: .starter),
        Cosmetic(id: "long",      slot: "hair", display: "Long",      unlock: .starter),

        // ── Hats
        Cosmetic(id: "beanie",     slot: "hat", display: "Beanie",     unlock: .starter),
        Cosmetic(id: "cap",        slot: "hat", display: "Cap",        unlock: .starter),
        Cosmetic(id: "wizard-hat", slot: "hat", display: "Wizard hat", unlock: .achievement(id: "well-read")),
        Cosmetic(id: "crown",      slot: "hat", display: "Crown",      unlock: .achievement(id: "elder-status")),
        Cosmetic(id: "halo",       slot: "hat", display: "Halo",       unlock: .achievement(id: "first-million")),
        Cosmetic(id: "jester",     slot: "hat", display: "Jester",     unlock: .drop(rarity: .uncommon)),
        Cosmetic(id: "octopus",    slot: "hat", display: "Octopus",    unlock: .drop(rarity: .rare)),

        // ── Eyewear
        Cosmetic(id: "round-glasses", slot: "eyewear", display: "Round glasses", unlock: .achievement(id: "first-light")),
        Cosmetic(id: "shades",        slot: "eyewear", display: "Shades",        unlock: .achievement(id: "swift-foot")),
        Cosmetic(id: "monocle",       slot: "eyewear", display: "Monocle",       unlock: .quest(id: "well-spoken")),
        Cosmetic(id: "heart-glasses", slot: "eyewear", display: "Heart glasses", unlock: .drop(rarity: .uncommon)),
        Cosmetic(id: "eye-patch",     slot: "eyewear", display: "Eye-patch",     unlock: .drop(rarity: .common)),

        // ── Capes
        Cosmetic(id: "red-cape",   slot: "cape", display: "Red cape",   unlock: .achievement(id: "frequent-flyer")),
        Cosmetic(id: "blue-cape",  slot: "cape", display: "Blue cape",  unlock: .quest(id: "stone-strong-arms")),
        Cosmetic(id: "rainbow",    slot: "cape", display: "Rainbow",    unlock: .drop(rarity: .rare)),
        Cosmetic(id: "bat-wings",  slot: "cape", display: "Bat wings",  unlock: .drop(rarity: .rare)),

        // ── Held items
        Cosmetic(id: "sword",        slot: "held", display: "Sword",        unlock: .achievement(id: "strong-start")),
        Cosmetic(id: "staff",        slot: "held", display: "Staff",        unlock: .achievement(id: "well-read")),
        Cosmetic(id: "shield",       slot: "held", display: "Shield",       unlock: .drop(rarity: .common)),
        Cosmetic(id: "magic-wand",   slot: "held", display: "Magic wand",   unlock: .drop(rarity: .uncommon)),
        Cosmetic(id: "crystal-ball", slot: "held", display: "Crystal ball", unlock: .drop(rarity: .rare)),
        Cosmetic(id: "mug",          slot: "held", display: "Mug",          unlock: .drop(rarity: .common)),
        Cosmetic(id: "fish",         slot: "held", display: "Fish",         unlock: .drop(rarity: .common)),
        Cosmetic(id: "rubber-duck",  slot: "held", display: "Rubber duck",  unlock: .drop(rarity: .rare)),

        // ── Shirts
        Cosmetic(id: "tunic",          slot: "shirt", display: "Tunic",          unlock: .starter),
        Cosmetic(id: "vest",           slot: "shirt", display: "Vest",           unlock: .quest(id: "iron-monster-cull")),
        Cosmetic(id: "striped",        slot: "shirt", display: "Striped shirt",  unlock: .drop(rarity: .common)),
        Cosmetic(id: "lab-coat",       slot: "shirt", display: "Lab coat",       unlock: .achievement(id: "deft-hands")),
        Cosmetic(id: "red-robe",       slot: "shirt", display: "Red robe",       unlock: .quest(id: "garden-wise")),
        Cosmetic(id: "jester-motley",  slot: "shirt", display: "Jester motley",  unlock: .drop(rarity: .uncommon)),

        // ── Pants
        Cosmetic(id: "long-pants",       slot: "pants", display: "Long pants",       unlock: .starter),
        Cosmetic(id: "shorts",           slot: "pants", display: "Shorts",           unlock: .starter),
        Cosmetic(id: "kilt",             slot: "pants", display: "Kilt",             unlock: .drop(rarity: .common)),
        Cosmetic(id: "bell-bottoms",     slot: "pants", display: "Bell-bottoms",     unlock: .drop(rarity: .uncommon)),
        Cosmetic(id: "blue-trousers",    slot: "pants", display: "Blue trousers",    unlock: .quest(id: "bazaar-coffers")),
        Cosmetic(id: "striped-leggings", slot: "pants", display: "Striped leggings", unlock: .drop(rarity: .uncommon)),

        // ── Belts
        Cosmetic(id: "leather", slot: "belt", display: "Leather belt", unlock: .starter),
        Cosmetic(id: "gold",    slot: "belt", display: "Gold belt",    unlock: .achievement(id: "first-shopkeeper")),
    ]

    static let byId: [String: Cosmetic] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// All starter cosmetics — the wardrobe defaults the player can choose
    /// from at hatch without needing to earn anything.
    static var starters: [Cosmetic] { all.filter { $0.unlock == .starter } }

    /// Slot display order in the wardrobe (also matches sprite z-order).
    static let slotOrder: [String] = ["hair", "eyewear", "hat", "shirt", "pants", "belt", "cape", "held"]

    static func find(_ id: String) -> Cosmetic? {
        byId[id]
    }

    /// Cosmetics in a slot — used by the wardrobe carousel to list options.
    static func bySlot(_ slot: String) -> [Cosmetic] {
        all.filter { $0.slot == slot }
    }

    /// Human-readable hint for how an unlock works, surfaced in the wardrobe
    /// silhouette tooltip ("Earn the First Blood achievement", etc).
    static func unlockHint(for cosmetic: Cosmetic) -> String {
        switch cosmetic.unlock {
        case .starter:
            return "Starter cosmetic."
        case let .achievement(id):
            let label = AchievementCatalog.byId[id]?.title ?? id
            return "Unlock by earning the \(label) achievement."
        case let .quest(id):
            let label = QuestCatalog.byId(id)?.name ?? id
            return "Quest reward: \(label)."
        case let .drop(rarity):
            switch rarity {
            case .common:   return "Rare drop from monsters."
            case .uncommon: return "Very rare drop from monsters."
            case .rare:     return "Exceptionally rare monster drop."
            }
        }
    }

    /// All cosmetics that can drop from random encounter victories.
    static var dropPool: [Cosmetic] {
        all.filter {
            if case .drop = $0.unlock { return true } else { return false }
        }
    }

    /// Cosmetic awarded by claiming a given quest, if any.
    static func cosmetic(forQuestId questId: String) -> Cosmetic? {
        all.first {
            if case let .quest(id) = $0.unlock { return id == questId } else { return false }
        }
    }

    /// Cosmetic awarded by earning a given achievement, if any.
    static func cosmetic(forAchievementId achievementId: String) -> Cosmetic? {
        all.first {
            if case let .achievement(id) = $0.unlock { return id == achievementId } else { return false }
        }
    }
}

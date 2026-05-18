import Foundation

/// One NPC the player can interact with. NPCs are tied to a region flavor and
/// expose either a shop (spend gold) or a trainer (spend EXP).
struct NPC: Identifiable, Hashable {
    enum Role: Hashable {
        case merchant(stock: [ShopOffer])
        case trainer(offerings: [TrainerOffering])
    }

    let id: String        // stable across launches
    let name: String
    let title: String     // short flavor descriptor, e.g., "Blacksmith"
    let greeting: String
    let role: Role
}

/// One item a merchant sells. `priceGold` is the cost; quantity is unlimited.
struct ShopOffer: Identifiable, Hashable {
    let itemId: String
    let priceGold: Int
    var id: String { itemId }
}

/// One thing a trainer teaches in exchange for EXP. Supports stat bumps
/// (permanent +N to a stat) and skill grants (learn a combat skill).
struct TrainerOffering: Identifiable, Hashable {
    let id: String
    let label: String
    let priceExp: Int
    let effect: Effect

    enum Effect: Hashable {
        case statBoost(stat: String, delta: Int)
        case healMax(by: Int)        // adds to hpMax via stat-equivalent boost
        case learnSkill(skillId: String)
    }
}

/// Population of each region flavor. v1 has one merchant + one trainer per
/// flavor. Step-gated discovery (only revealing some NPCs after N LoC) lands
/// in a follow-up.
enum NPCRoster {
    static func npcs(for flavor: Region.Flavor) -> [NPC] {
        switch flavor {
        case .stonework:    return stoneworkNPCs
        case .ironFortress: return ironFortressNPCs
        case .gardenVillage: return gardenVillageNPCs
        case .bazaar:       return bazaarNPCs
        case .openSteppe:   return openSteppeNPCs
        case .wilderness:   return wildernessNPCs
        }
    }

    // MARK: - Rosters

    private static let stoneworkNPCs: [NPC] = [
        NPC(
            id: "stonework-quarrymaster",
            name: "Trev",
            title: "Quarrymaster",
            greeting: "Need supplies before your next descent?",
            role: .merchant(stock: [
                ShopOffer(itemId: "bread",            priceGold: 5),
                ShopOffer(itemId: "hearty-meat",      priceGold: 15),
                ShopOffer(itemId: "small-sp-potion",  priceGold: 12),
            ])
        ),
        NPC(
            id: "stonework-archmason",
            name: "Penn",
            title: "Archmason",
            greeting: "Strength is built one stone at a time.",
            role: .trainer(offerings: [
                TrainerOffering(id: "str-1", label: "+1 STR", priceExp: 25, effect: .statBoost(stat: "STR", delta: 1)),
                TrainerOffering(id: "dex-1", label: "+1 DEX", priceExp: 25, effect: .statBoost(stat: "DEX", delta: 1)),
                TrainerOffering(id: "skill-strike", label: "Learn Power Strike", priceExp: 40, effect: .learnSkill(skillId: "strike")),
                TrainerOffering(id: "skill-block",  label: "Learn Block",        priceExp: 30, effect: .learnSkill(skillId: "block")),
            ])
        ),
    ]

    private static let ironFortressNPCs: [NPC] = [
        NPC(
            id: "iron-blacksmith",
            name: "Vyn",
            title: "Blacksmith",
            greeting: "Forged to your needs, friend.",
            role: .merchant(stock: [
                ShopOffer(itemId: "hearty-meat",      priceGold: 18),
                ShopOffer(itemId: "feast",            priceGold: 60),
                ShopOffer(itemId: "medium-sp-potion", priceGold: 35),
            ])
        ),
        NPC(
            id: "iron-drillmaster",
            name: "Korr",
            title: "Drillmaster",
            greeting: "Iron sharpens iron. Discipline first.",
            role: .trainer(offerings: [
                TrainerOffering(id: "str-2", label: "+1 STR", priceExp: 20, effect: .statBoost(stat: "STR", delta: 1)),
                TrainerOffering(id: "agi-2", label: "+1 AGI", priceExp: 30, effect: .statBoost(stat: "AGI", delta: 1)),
                TrainerOffering(id: "skill-pierce", label: "Learn Pierce", priceExp: 40, effect: .learnSkill(skillId: "pierce")),
                TrainerOffering(id: "skill-weaken", label: "Learn Weaken", priceExp: 35, effect: .learnSkill(skillId: "weaken")),
            ])
        ),
    ]

    private static let gardenVillageNPCs: [NPC] = [
        NPC(
            id: "garden-botanist",
            name: "Sage",
            title: "Botanist",
            greeting: "The flora is the pharmacy.",
            role: .merchant(stock: [
                ShopOffer(itemId: "bread",            priceGold: 4),
                ShopOffer(itemId: "hearty-meat",      priceGold: 14),
                ShopOffer(itemId: "feast",            priceGold: 55),
                ShopOffer(itemId: "small-sp-potion",  priceGold: 10),
            ])
        ),
        NPC(
            id: "garden-scholar",
            name: "Wren",
            title: "Garden Scholar",
            greeting: "Knowledge grows in every leaf.",
            role: .trainer(offerings: [
                TrainerOffering(id: "int-1", label: "+1 INT", priceExp: 25, effect: .statBoost(stat: "INT", delta: 1)),
                TrainerOffering(id: "cha-1", label: "+1 CHA", priceExp: 25, effect: .statBoost(stat: "CHA", delta: 1)),
                TrainerOffering(id: "skill-fireball", label: "Learn Fireball", priceExp: 60, effect: .learnSkill(skillId: "fireball")),
                TrainerOffering(id: "skill-mend",     label: "Learn Mend",     priceExp: 45, effect: .learnSkill(skillId: "mend")),
            ])
        ),
    ]

    private static let bazaarNPCs: [NPC] = [
        NPC(
            id: "bazaar-haggler",
            name: "Tox",
            title: "Haggler",
            greeting: "I have what you didn't know you needed.",
            role: .merchant(stock: [
                ShopOffer(itemId: "hearty-meat",      priceGold: 12),
                ShopOffer(itemId: "feast",            priceGold: 50),
                ShopOffer(itemId: "small-sp-potion",  priceGold: 8),
                ShopOffer(itemId: "medium-sp-potion", priceGold: 28),
            ])
        ),
        NPC(
            id: "bazaar-orator",
            name: "Lia",
            title: "Street Orator",
            greeting: "Charm is the cheapest currency.",
            role: .trainer(offerings: [
                TrainerOffering(id: "cha-2", label: "+1 CHA", priceExp: 20, effect: .statBoost(stat: "CHA", delta: 1)),
                TrainerOffering(id: "dex-3", label: "+1 DEX", priceExp: 30, effect: .statBoost(stat: "DEX", delta: 1)),
                TrainerOffering(id: "skill-inspire", label: "Learn Inspire-Attack", priceExp: 40, effect: .learnSkill(skillId: "inspire")),
                TrainerOffering(id: "skill-escape",  label: "Learn Escape",         priceExp: 35, effect: .learnSkill(skillId: "escape")),
            ])
        ),
    ]

    private static let openSteppeNPCs: [NPC] = [
        NPC(
            id: "steppe-trader",
            name: "Mira",
            title: "Caravan Trader",
            greeting: "Wind's been kind. Want to barter?",
            role: .merchant(stock: [
                ShopOffer(itemId: "bread",            priceGold: 5),
                ShopOffer(itemId: "hearty-meat",      priceGold: 15),
                ShopOffer(itemId: "small-sp-potion",  priceGold: 12),
            ])
        ),
        NPC(
            id: "steppe-rider",
            name: "Khel",
            title: "Wind Rider",
            greeting: "Speed is what kept us alive out there.",
            role: .trainer(offerings: [
                TrainerOffering(id: "agi-1", label: "+1 AGI", priceExp: 20, effect: .statBoost(stat: "AGI", delta: 1)),
                TrainerOffering(id: "str-3", label: "+1 STR", priceExp: 35, effect: .statBoost(stat: "STR", delta: 1)),
                TrainerOffering(id: "skill-greater-heal", label: "Learn Greater Heal", priceExp: 80, effect: .learnSkill(skillId: "greater-heal")),
            ])
        ),
    ]

    private static let wildernessNPCs: [NPC] = [
        NPC(
            id: "wild-hermit",
            name: "Roon",
            title: "Hermit",
            greeting: "Few visitors out here. Stay a while.",
            role: .merchant(stock: [
                ShopOffer(itemId: "bread",            priceGold: 6),
                ShopOffer(itemId: "small-sp-potion",  priceGold: 14),
            ])
        ),
    ]
}

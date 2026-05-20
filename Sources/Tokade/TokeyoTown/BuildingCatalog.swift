import SwiftUI

/// Catalog of the 40 buildings — 8 per biome. Each entry has a cost, a
/// rendering color, and a glyph used by the procedural-placeholder
/// renderer. When we swap in Kenney/custom sprites, only `glyph` /
/// `color` become unused; the rest of the data stays.
enum BuildingCatalog {
    struct Building: Hashable, Identifiable {
        let id: String
        let displayName: String
        let biome: TokeyoTownState.Biome
        let cost: TokeyoTownState.Resources
        let color: Color
        /// Single emoji or character used for the procedural placeholder.
        let glyph: String
        /// One-line flavor text shown in the building palette.
        let blurb: String
    }

    static let all: [Building] = plain + desert + tundra + forest + beach

    static func buildings(for biome: TokeyoTownState.Biome) -> [Building] {
        all.filter { $0.biome == biome }
    }

    static func find(_ id: String) -> Building? {
        all.first(where: { $0.id == id })
    }

    // MARK: - Plain (8)

    static let plain: [Building] = [
        Building(id: "plain-cottage", displayName: "Cottage", biome: .plain,
                 cost: .init(coin: 20, lumber: 8),
                 color: Color(red: 0.86, green: 0.55, blue: 0.42), glyph: "🏠",
                 blurb: "A small home where a townsfolk lives."),
        Building(id: "plain-grocer", displayName: "Grocer", biome: .plain,
                 cost: .init(coin: 35, lumber: 6, industry: 2),
                 color: Color(red: 0.95, green: 0.80, blue: 0.30), glyph: "🛒",
                 blurb: "Fresh produce, friendly chatter."),
        Building(id: "plain-park", displayName: "Park", biome: .plain,
                 cost: .init(coin: 15, growth: 4),
                 color: Color(red: 0.45, green: 0.78, blue: 0.42), glyph: "🌳",
                 blurb: "Townsfolk loiter here on slow afternoons."),
        Building(id: "plain-school", displayName: "School", biome: .plain,
                 cost: .init(coin: 50, knowledge: 10, lumber: 8),
                 color: Color(red: 0.78, green: 0.42, blue: 0.42), glyph: "🏫",
                 blurb: "Where the kids learn to read."),
        Building(id: "plain-bakery", displayName: "Bakery", biome: .plain,
                 cost: .init(coin: 40, lumber: 4, industry: 3),
                 color: Color(red: 0.92, green: 0.72, blue: 0.45), glyph: "🥐",
                 blurb: "The smell drifts three blocks."),
        Building(id: "plain-clocktower", displayName: "Clock Tower", biome: .plain,
                 cost: .init(coin: 80, industry: 10, inspiration: 2),
                 color: Color(red: 0.65, green: 0.55, blue: 0.78), glyph: "🕰",
                 blurb: "Marks the hour. Sometimes wrong."),
        Building(id: "plain-fountain", displayName: "Fountain", biome: .plain,
                 cost: .init(coin: 30, stability: 3),
                 color: Color(red: 0.55, green: 0.78, blue: 0.92), glyph: "⛲",
                 blurb: "Coins at the bottom. Wishes above."),
        Building(id: "plain-library", displayName: "Library", biome: .plain,
                 cost: .init(coin: 60, knowledge: 14, lumber: 6),
                 color: Color(red: 0.50, green: 0.34, blue: 0.62), glyph: "📚",
                 blurb: "Knowledge condenses here.")
    ]

    // MARK: - Desert (8)

    static let desert: [Building] = [
        Building(id: "desert-adobe", displayName: "Adobe Home", biome: .desert,
                 cost: .init(coin: 22, lumber: 4, industry: 4),
                 color: Color(red: 0.78, green: 0.55, blue: 0.36), glyph: "🏚",
                 blurb: "Cool walls. Warm tile floors."),
        Building(id: "desert-oasis", displayName: "Oasis", biome: .desert,
                 cost: .init(coin: 45, growth: 8),
                 color: Color(red: 0.42, green: 0.72, blue: 0.55), glyph: "🌴",
                 blurb: "Water and shade. The whole town comes here."),
        Building(id: "desert-market", displayName: "Souk", biome: .desert,
                 cost: .init(coin: 40, lumber: 4, industry: 4),
                 color: Color(red: 0.95, green: 0.62, blue: 0.30), glyph: "🏬",
                 blurb: "Spice. Cloth. Conversation."),
        Building(id: "desert-observatory", displayName: "Observatory", biome: .desert,
                 cost: .init(coin: 75, knowledge: 12, inspiration: 4),
                 color: Color(red: 0.36, green: 0.30, blue: 0.62), glyph: "🔭",
                 blurb: "Cleaner skies than anywhere else."),
        Building(id: "desert-windmill", displayName: "Windmill", biome: .desert,
                 cost: .init(coin: 35, lumber: 6, industry: 8),
                 color: Color(red: 0.86, green: 0.78, blue: 0.55), glyph: "🪁",
                 blurb: "Catches what little wind there is."),
        Building(id: "desert-tea", displayName: "Tea House", biome: .desert,
                 cost: .init(coin: 30, stability: 3, growth: 2),
                 color: Color(red: 0.92, green: 0.55, blue: 0.42), glyph: "🍵",
                 blurb: "Mint, sugar, ceremony."),
        Building(id: "desert-pyramid", displayName: "Stepped Pyramid", biome: .desert,
                 cost: .init(coin: 110, knowledge: 6, industry: 16, inspiration: 4),
                 color: Color(red: 0.78, green: 0.62, blue: 0.36), glyph: "🔺",
                 blurb: "The reason this town is on every postcard."),
        Building(id: "desert-cistern", displayName: "Cistern", biome: .desert,
                 cost: .init(coin: 28, industry: 6, stability: 4),
                 color: Color(red: 0.55, green: 0.62, blue: 0.78), glyph: "💧",
                 blurb: "Holds the rare rain.")
    ]

    // MARK: - Tundra (8)

    static let tundra: [Building] = [
        Building(id: "tundra-cabin", displayName: "Log Cabin", biome: .tundra,
                 cost: .init(coin: 20, lumber: 10),
                 color: Color(red: 0.42, green: 0.30, blue: 0.22), glyph: "🛖",
                 blurb: "Smoke from the chimney all winter."),
        Building(id: "tundra-icefishing", displayName: "Ice Fishing Hut", biome: .tundra,
                 cost: .init(coin: 25, lumber: 4, industry: 3),
                 color: Color(red: 0.55, green: 0.78, blue: 0.92), glyph: "🎣",
                 blurb: "Peaceful, except for the wind."),
        Building(id: "tundra-pines", displayName: "Pine Grove", biome: .tundra,
                 cost: .init(coin: 12, growth: 5),
                 color: Color(red: 0.20, green: 0.42, blue: 0.30), glyph: "🌲",
                 blurb: "Snow on the branches all year."),
        Building(id: "tundra-forge", displayName: "Forge", biome: .tundra,
                 cost: .init(coin: 50, lumber: 4, industry: 12),
                 color: Color(red: 0.55, green: 0.30, blue: 0.22), glyph: "🔨",
                 blurb: "The only warm building for miles."),
        Building(id: "tundra-mead", displayName: "Mead Hall", biome: .tundra,
                 cost: .init(coin: 60, lumber: 10, stability: 4, growth: 4),
                 color: Color(red: 0.65, green: 0.42, blue: 0.30), glyph: "🍺",
                 blurb: "Long tables. Long songs."),
        Building(id: "tundra-onsen", displayName: "Hot Spring", biome: .tundra,
                 cost: .init(coin: 45, stability: 6, growth: 2),
                 color: Color(red: 0.92, green: 0.78, blue: 0.78), glyph: "♨",
                 blurb: "Steam against the cold."),
        Building(id: "tundra-watchtower", displayName: "Watch Tower", biome: .tundra,
                 cost: .init(coin: 70, industry: 10, stability: 8),
                 color: Color(red: 0.42, green: 0.45, blue: 0.55), glyph: "🗼",
                 blurb: "Sees the next valley over."),
        Building(id: "tundra-shrine", displayName: "Snow Shrine", biome: .tundra,
                 cost: .init(coin: 55, lumber: 4, inspiration: 6),
                 color: Color(red: 0.78, green: 0.42, blue: 0.55), glyph: "⛩",
                 blurb: "Bells on red ribbons.")
    ]

    // MARK: - Forest (8)

    static let forest: [Building] = [
        Building(id: "forest-treehouse", displayName: "Tree House", biome: .forest,
                 cost: .init(coin: 25, lumber: 12),
                 color: Color(red: 0.55, green: 0.36, blue: 0.22), glyph: "🌳",
                 blurb: "A ladder. A door. A view."),
        Building(id: "forest-mushroom", displayName: "Mushroom Hut", biome: .forest,
                 cost: .init(coin: 30, lumber: 4, growth: 6),
                 color: Color(red: 0.86, green: 0.45, blue: 0.42), glyph: "🍄",
                 blurb: "Spotted, large, hospitable."),
        Building(id: "forest-shrine", displayName: "Moss Shrine", biome: .forest,
                 cost: .init(coin: 35, inspiration: 4, growth: 4),
                 color: Color(red: 0.30, green: 0.55, blue: 0.42), glyph: "⛩",
                 blurb: "Older than anyone living."),
        Building(id: "forest-mill", displayName: "Water Mill", biome: .forest,
                 cost: .init(coin: 45, lumber: 8, industry: 8),
                 color: Color(red: 0.45, green: 0.36, blue: 0.30), glyph: "🌊",
                 blurb: "Powered by the river. Quietly."),
        Building(id: "forest-apothecary", displayName: "Apothecary", biome: .forest,
                 cost: .init(coin: 50, knowledge: 8, growth: 4),
                 color: Color(red: 0.55, green: 0.62, blue: 0.30), glyph: "🧪",
                 blurb: "Hangs herbs from the rafters."),
        Building(id: "forest-pond", displayName: "Lily Pond", biome: .forest,
                 cost: .init(coin: 22, growth: 6),
                 color: Color(red: 0.30, green: 0.62, blue: 0.55), glyph: "🪷",
                 blurb: "Koi. Lilies. Considered reflection."),
        Building(id: "forest-library", displayName: "Wood Library", biome: .forest,
                 cost: .init(coin: 65, knowledge: 14, lumber: 10),
                 color: Color(red: 0.42, green: 0.30, blue: 0.20), glyph: "📚",
                 blurb: "Bookbinder lives upstairs."),
        Building(id: "forest-bridge", displayName: "Stone Bridge", biome: .forest,
                 cost: .init(coin: 40, industry: 8, stability: 4),
                 color: Color(red: 0.62, green: 0.62, blue: 0.55), glyph: "🌉",
                 blurb: "Over the slowest part of the stream.")
    ]

    // MARK: - Beach (8)

    static let beach: [Building] = [
        Building(id: "beach-cottage", displayName: "Pastel Cottage", biome: .beach,
                 cost: .init(coin: 20, lumber: 6),
                 color: Color(red: 0.95, green: 0.62, blue: 0.78), glyph: "🏡",
                 blurb: "Pale pink walls. Faded by salt."),
        Building(id: "beach-lighthouse", displayName: "Lighthouse", biome: .beach,
                 cost: .init(coin: 80, industry: 12, stability: 8),
                 color: Color(red: 0.92, green: 0.42, blue: 0.42), glyph: "🗼",
                 blurb: "Sweeps every twelve seconds."),
        Building(id: "beach-pier", displayName: "Pier", biome: .beach,
                 cost: .init(coin: 35, lumber: 10, industry: 4),
                 color: Color(red: 0.55, green: 0.42, blue: 0.30), glyph: "🛥",
                 blurb: "Long boards. Long shadows at sunset."),
        Building(id: "beach-icecream", displayName: "Ice Cream Stand", biome: .beach,
                 cost: .init(coin: 30, industry: 3, growth: 3),
                 color: Color(red: 0.95, green: 0.78, blue: 0.42), glyph: "🍦",
                 blurb: "Open seasonally. Or whenever it feels open."),
        Building(id: "beach-cafe", displayName: "Boardwalk Café", biome: .beach,
                 cost: .init(coin: 45, lumber: 4, industry: 3, growth: 2),
                 color: Color(red: 0.78, green: 0.55, blue: 0.42), glyph: "☕",
                 blurb: "Outdoor seating only."),
        Building(id: "beach-aquarium", displayName: "Aquarium", biome: .beach,
                 cost: .init(coin: 75, knowledge: 10, industry: 6, inspiration: 2),
                 color: Color(red: 0.42, green: 0.62, blue: 0.92), glyph: "🐠",
                 blurb: "Children press their noses to the glass."),
        Building(id: "beach-gardens", displayName: "Beach Gardens", biome: .beach,
                 cost: .init(coin: 25, growth: 8),
                 color: Color(red: 0.55, green: 0.78, blue: 0.42), glyph: "🌺",
                 blurb: "Hibiscus, sand grass, glass-bead paths."),
        Building(id: "beach-shrine", displayName: "Sea Shrine", biome: .beach,
                 cost: .init(coin: 55, stability: 3, inspiration: 6),
                 color: Color(red: 0.92, green: 0.30, blue: 0.42), glyph: "⛩",
                 blurb: "Bells, rope, salt-bleached wood.")
    ]
}

import SwiftUI

/// Catalog of 40 buildings (8 per biome). v2 — each entry now carries a
/// composable `BuildingShape` recipe so the renderer can draw the building
/// itself instead of putting a glyph on a brick. Footprint defaults to
/// 1×1 from the shape; "major" buildings (libraries, observatories, etc.)
/// are 2×1 or 2×2.
///
/// Costs were rebalanced in v2 — see ADR-0006 addendum:
///   - Coin earn nerfed (1/1k → 1/4k tokens), so we don't bump coin costs
///   - Other resources still earn slowly; costs roughly 2-3× v1
///   - Major buildings (footprint > 1) require multiple scarce resources,
///     not just lots of coin.
enum BuildingCatalog {
    struct Building: Hashable, Identifiable {
        let id: String
        let displayName: String
        let biome: TokeyoTownState.Biome
        let cost: TokeyoTownState.Resources
        let shape: BuildingShape
        /// Single emoji or character used in the palette row + the small
        /// building badge drawn beside the building.
        let glyph: String
        let blurb: String
        /// True when this building counts as housing — drives townsfolk
        /// home assignment in `TownsfolkSpawner`.
        var isHome: Bool = false
        var footprint: BuildingShape.Footprint { shape.footprint }
    }

    static let all: [Building] = plain + desert + tundra + forest + beach

    static func buildings(for biome: TokeyoTownState.Biome) -> [Building] {
        all.filter { $0.biome == biome }
    }

    static func find(_ id: String) -> Building? {
        all.first(where: { $0.id == id })
    }

    // Common color references reused across recipes
    private static let trimDark = Color(red: 0.18, green: 0.12, blue: 0.10)
    private static let trimWarm = Color(red: 0.42, green: 0.30, blue: 0.22)

    // MARK: - Plain (8)

    static let plain: [Building] = [
        Building(
            id: "plain-cottage", displayName: "Cottage", biome: .plain,
            cost: .init(coin: 50, lumber: 18),
            shape: .cottage(
                wall: Color(red: 0.94, green: 0.85, blue: 0.62),
                roof: Color(red: 0.78, green: 0.30, blue: 0.30),
                trim: trimWarm
            ),
            glyph: "🏠", blurb: "A small home. Houses one townsfolk.", isHome: true
        ),
        Building(
            id: "plain-grocer", displayName: "Grocer", biome: .plain,
            cost: .init(coin: 90, lumber: 14, industry: 6),
            shape: .twoStory(
                wall: Color(red: 0.95, green: 0.78, blue: 0.34),
                upper: Color(red: 0.92, green: 0.70, blue: 0.30),
                roof: Color(red: 0.55, green: 0.30, blue: 0.20),
                trim: trimWarm
            ),
            glyph: "🛒", blurb: "Produce out front, gossip in the back."
        ),
        Building(
            id: "plain-park", displayName: "Park", biome: .plain,
            cost: .init(coin: 35, growth: 10),
            shape: .park(
                grass: Color(red: 0.45, green: 0.78, blue: 0.42),
                accent: Color(red: 0.22, green: 0.55, blue: 0.30)
            ),
            glyph: "🌳", blurb: "Townsfolk loiter here on slow afternoons."
        ),
        Building(
            id: "plain-school", displayName: "School", biome: .plain,
            cost: .init(coin: 140, knowledge: 26, lumber: 22),
            shape: .bigHall(
                wall: Color(red: 0.78, green: 0.42, blue: 0.42),
                roof: Color(red: 0.42, green: 0.20, blue: 0.18),
                trim: trimDark
            ),
            glyph: "🏫", blurb: "Where the kids learn to read."
        ),
        Building(
            id: "plain-bakery", displayName: "Bakery", biome: .plain,
            cost: .init(coin: 100, lumber: 10, industry: 8),
            shape: .cottage(
                wall: Color(red: 0.92, green: 0.72, blue: 0.45),
                roof: Color(red: 0.60, green: 0.32, blue: 0.20),
                trim: trimWarm,
                accent: .white
            ),
            glyph: "🥐", blurb: "The smell drifts three blocks."
        ),
        Building(
            id: "plain-clocktower", displayName: "Clock Tower", biome: .plain,
            cost: .init(coin: 220, industry: 26, inspiration: 6),
            shape: .tower(
                wall: Color(red: 0.65, green: 0.55, blue: 0.78),
                capColor: Color(red: 0.35, green: 0.28, blue: 0.55)
            ),
            glyph: "🕰", blurb: "Marks the hour. Sometimes wrong."
        ),
        Building(
            id: "plain-fountain", displayName: "Fountain", biome: .plain,
            cost: .init(coin: 70, stability: 6),
            shape: .waterFeature(
                stone: Color(red: 0.75, green: 0.75, blue: 0.72),
                water: Color(red: 0.42, green: 0.74, blue: 0.92)
            ),
            glyph: "⛲", blurb: "Coins at the bottom. Wishes above."
        ),
        Building(
            id: "plain-library", displayName: "Library", biome: .plain,
            cost: .init(coin: 180, knowledge: 32, lumber: 16),
            shape: BuildingShape(
                footprint: .init(2, 2),
                stories: [
                    .init(height: 22, inset: 0,
                          wallColor: Color(red: 0.50, green: 0.34, blue: 0.62),
                          trimColor: Color(red: 0.95, green: 0.85, blue: 0.42)),
                    .init(height: 14, inset: 6,
                          wallColor: Color(red: 0.42, green: 0.28, blue: 0.55),
                          trimColor: Color(red: 0.95, green: 0.85, blue: 0.42)),
                ],
                roof: .dome(height: 14, color: Color(red: 0.95, green: 0.85, blue: 0.42)),
                ornament: nil, accent: nil
            ),
            glyph: "📚", blurb: "Knowledge condenses here."
        ),
        Building(
            id: "plain-rowhouse", displayName: "Row House", biome: .plain,
            cost: .init(coin: 70, lumber: 22),
            shape: .twoStory(
                wall: Color(red: 0.78, green: 0.55, blue: 0.42),
                upper: Color(red: 0.62, green: 0.42, blue: 0.32),
                roof: Color(red: 0.35, green: 0.20, blue: 0.18),
                trim: trimWarm
            ),
            glyph: "🏘", blurb: "Skinny, stacked, neighborly.", isHome: true
        ),
    ]

    // MARK: - Desert (8)

    static let desert: [Building] = [
        Building(
            id: "desert-adobe", displayName: "Adobe Home", biome: .desert,
            cost: .init(coin: 55, lumber: 10, industry: 8),
            shape: .cottage(
                wall: Color(red: 0.85, green: 0.62, blue: 0.42),
                roof: Color(red: 0.65, green: 0.40, blue: 0.22),
                trim: trimWarm
            ),
            glyph: "🏚", blurb: "Cool walls. Warm tile floors.", isHome: true
        ),
        Building(
            id: "desert-oasis", displayName: "Oasis", biome: .desert,
            cost: .init(coin: 100, growth: 16),
            shape: .park(
                grass: Color(red: 0.42, green: 0.72, blue: 0.55),
                accent: Color(red: 0.22, green: 0.55, blue: 0.30)
            ),
            glyph: "🌴", blurb: "Water and shade. The whole town comes here."
        ),
        Building(
            id: "desert-market", displayName: "Souk", biome: .desert,
            cost: .init(coin: 105, lumber: 12, industry: 10),
            shape: .twoStory(
                wall: Color(red: 0.95, green: 0.62, blue: 0.30),
                upper: Color(red: 0.85, green: 0.50, blue: 0.25),
                roof: Color(red: 0.55, green: 0.28, blue: 0.16),
                trim: trimWarm
            ),
            glyph: "🏬", blurb: "Spice. Cloth. Conversation."
        ),
        Building(
            id: "desert-observatory", displayName: "Observatory", biome: .desert,
            cost: .init(coin: 200, knowledge: 28, inspiration: 10),
            shape: .dome(
                wall: Color(red: 0.40, green: 0.34, blue: 0.62),
                dome: Color(red: 0.95, green: 0.85, blue: 0.42),
                height: 18
            ),
            glyph: "🔭", blurb: "Cleaner skies than anywhere else."
        ),
        Building(
            id: "desert-windmill", displayName: "Windmill", biome: .desert,
            cost: .init(coin: 90, lumber: 14, industry: 18),
            shape: .windmill(
                wall: Color(red: 0.86, green: 0.78, blue: 0.55),
                sail: trimWarm
            ),
            glyph: "🪁", blurb: "Catches what little wind there is."
        ),
        Building(
            id: "desert-tea", displayName: "Tea House", biome: .desert,
            cost: .init(coin: 80, stability: 7, growth: 6),
            shape: .shrine(
                wall: Color(red: 0.92, green: 0.55, blue: 0.42),
                roof: Color(red: 0.60, green: 0.20, blue: 0.20)
            ),
            glyph: "🍵", blurb: "Mint, sugar, ceremony."
        ),
        Building(
            id: "desert-pyramid", displayName: "Stepped Pyramid", biome: .desert,
            cost: .init(coin: 320, knowledge: 18, industry: 36, inspiration: 10),
            shape: .pyramid(
                stone: Color(red: 0.78, green: 0.62, blue: 0.36),
                capColor: Color(red: 0.95, green: 0.85, blue: 0.30)
            ),
            glyph: "🔺", blurb: "The reason this town is on every postcard."
        ),
        Building(
            id: "desert-cistern", displayName: "Cistern", biome: .desert,
            cost: .init(coin: 75, industry: 12, stability: 9),
            shape: .waterFeature(
                stone: Color(red: 0.55, green: 0.62, blue: 0.78),
                water: Color(red: 0.30, green: 0.55, blue: 0.85)
            ),
            glyph: "💧", blurb: "Holds the rare rain."
        ),
        Building(
            id: "desert-yurt", displayName: "Yurt", biome: .desert,
            cost: .init(coin: 55, lumber: 14),
            shape: BuildingShape(
                footprint: .init(1, 1),
                stories: [.init(height: 14, inset: 0,
                                wallColor: Color(red: 0.92, green: 0.78, blue: 0.55),
                                trimColor: trimWarm)],
                roof: .hip(height: 14, color: Color(red: 0.62, green: 0.30, blue: 0.22)),
                ornament: .spire(height: 4, color: Color(red: 0.95, green: 0.85, blue: 0.30)),
                accent: nil
            ),
            glyph: "⛺", blurb: "Felt walls, lattice frame, warm at night.", isHome: true
        ),
    ]

    // MARK: - Tundra (8)

    static let tundra: [Building] = [
        Building(
            id: "tundra-cabin", displayName: "Log Cabin", biome: .tundra,
            cost: .init(coin: 55, lumber: 22),
            shape: .cottage(
                wall: Color(red: 0.42, green: 0.30, blue: 0.22),
                roof: Color(red: 0.95, green: 0.95, blue: 0.97),
                trim: trimDark
            ),
            glyph: "🛖", blurb: "Smoke from the chimney all winter.", isHome: true
        ),
        Building(
            id: "tundra-icefishing", displayName: "Ice Fishing Hut", biome: .tundra,
            cost: .init(coin: 65, lumber: 10, industry: 6),
            shape: .cottage(
                wall: Color(red: 0.55, green: 0.78, blue: 0.92),
                roof: Color(red: 0.32, green: 0.50, blue: 0.62),
                trim: trimDark
            ),
            glyph: "🎣", blurb: "Peaceful, except for the wind."
        ),
        Building(
            id: "tundra-pines", displayName: "Pine Grove", biome: .tundra,
            cost: .init(coin: 28, growth: 10),
            shape: .park(
                grass: Color(red: 0.92, green: 0.94, blue: 0.97),
                accent: Color(red: 0.20, green: 0.42, blue: 0.30)
            ),
            glyph: "🌲", blurb: "Snow on the branches all year."
        ),
        Building(
            id: "tundra-forge", displayName: "Forge", biome: .tundra,
            cost: .init(coin: 130, lumber: 10, industry: 26),
            shape: .twoStory(
                wall: Color(red: 0.55, green: 0.30, blue: 0.22),
                upper: Color(red: 0.42, green: 0.22, blue: 0.18),
                roof: Color(red: 0.30, green: 0.18, blue: 0.16),
                trim: trimDark
            ),
            glyph: "🔨", blurb: "The only warm building for miles."
        ),
        Building(
            id: "tundra-mead", displayName: "Mead Hall", biome: .tundra,
            cost: .init(coin: 160, lumber: 22, stability: 8, growth: 8),
            shape: .bigHall(
                wall: Color(red: 0.65, green: 0.42, blue: 0.30),
                roof: Color(red: 0.30, green: 0.20, blue: 0.15),
                trim: trimDark
            ),
            glyph: "🍺", blurb: "Long tables. Long songs."
        ),
        Building(
            id: "tundra-onsen", displayName: "Hot Spring", biome: .tundra,
            cost: .init(coin: 110, stability: 12, growth: 4),
            shape: .waterFeature(
                stone: Color(red: 0.55, green: 0.55, blue: 0.62),
                water: Color(red: 0.92, green: 0.78, blue: 0.78)
            ),
            glyph: "♨", blurb: "Steam against the cold."),
        Building(
            id: "tundra-watchtower", displayName: "Watch Tower", biome: .tundra,
            cost: .init(coin: 190, industry: 22, stability: 14),
            shape: .tower(
                wall: Color(red: 0.42, green: 0.45, blue: 0.55),
                capColor: Color(red: 0.30, green: 0.32, blue: 0.42)
            ),
            glyph: "🗼", blurb: "Sees the next valley over."
        ),
        Building(
            id: "tundra-shrine", displayName: "Snow Shrine", biome: .tundra,
            cost: .init(coin: 130, lumber: 10, inspiration: 12),
            shape: .shrine(
                wall: Color(red: 0.78, green: 0.42, blue: 0.55),
                roof: Color(red: 0.55, green: 0.20, blue: 0.30)
            ),
            glyph: "⛩", blurb: "Bells on red ribbons."
        ),
        Building(
            id: "tundra-lodge", displayName: "Stone Lodge", biome: .tundra,
            cost: .init(coin: 120, lumber: 18, stability: 6),
            shape: .bigHall(
                wall: Color(red: 0.55, green: 0.55, blue: 0.62),
                roof: Color(red: 0.78, green: 0.78, blue: 0.84),
                trim: trimDark
            ),
            glyph: "🏔", blurb: "Two families. Stone hearth.", isHome: true
        ),
    ]

    // MARK: - Forest (8)

    static let forest: [Building] = [
        Building(
            id: "forest-treehouse", displayName: "Tree House", biome: .forest,
            cost: .init(coin: 60, lumber: 26),
            shape: .twoStory(
                wall: Color(red: 0.55, green: 0.36, blue: 0.22),
                upper: Color(red: 0.42, green: 0.28, blue: 0.18),
                roof: Color(red: 0.30, green: 0.55, blue: 0.30),
                trim: trimDark
            ),
            glyph: "🌳", blurb: "A ladder. A door. A view.", isHome: true
        ),
        Building(
            id: "forest-mushroom", displayName: "Mushroom Hut", biome: .forest,
            cost: .init(coin: 75, lumber: 10, growth: 12),
            shape: BuildingShape(
                footprint: .init(1, 1),
                stories: [.init(height: 14, inset: 0,
                                wallColor: Color(red: 0.96, green: 0.94, blue: 0.85),
                                trimColor: trimDark)],
                roof: .dome(height: 16, color: Color(red: 0.86, green: 0.30, blue: 0.30)),
                ornament: nil,
                accent: .white
            ),
            glyph: "🍄", blurb: "Spotted, large, hospitable.", isHome: true
        ),
        Building(
            id: "forest-shrine", displayName: "Moss Shrine", biome: .forest,
            cost: .init(coin: 85, lumber: 10, inspiration: 10),
            shape: .shrine(
                wall: Color(red: 0.30, green: 0.55, blue: 0.42),
                roof: Color(red: 0.18, green: 0.32, blue: 0.22)
            ),
            glyph: "⛩", blurb: "Older than anyone living."
        ),
        Building(
            id: "forest-mill", displayName: "Water Mill", biome: .forest,
            cost: .init(coin: 115, lumber: 18, industry: 18),
            shape: .twoStory(
                wall: Color(red: 0.45, green: 0.36, blue: 0.30),
                upper: Color(red: 0.36, green: 0.28, blue: 0.22),
                roof: Color(red: 0.22, green: 0.42, blue: 0.50),
                trim: trimDark
            ),
            glyph: "🌊", blurb: "Powered by the river. Quietly."
        ),
        Building(
            id: "forest-apothecary", displayName: "Apothecary", biome: .forest,
            cost: .init(coin: 130, knowledge: 18, growth: 10),
            shape: .twoStory(
                wall: Color(red: 0.55, green: 0.62, blue: 0.30),
                upper: Color(red: 0.42, green: 0.50, blue: 0.22),
                roof: Color(red: 0.30, green: 0.32, blue: 0.20),
                trim: trimDark
            ),
            glyph: "🧪", blurb: "Hangs herbs from the rafters."
        ),
        Building(
            id: "forest-pond", displayName: "Lily Pond", biome: .forest,
            cost: .init(coin: 55, growth: 14),
            shape: .waterFeature(
                stone: Color(red: 0.30, green: 0.55, blue: 0.45),
                water: Color(red: 0.30, green: 0.62, blue: 0.55)
            ),
            glyph: "🪷", blurb: "Koi. Lilies. Considered reflection."
        ),
        Building(
            id: "forest-library", displayName: "Wood Library", biome: .forest,
            cost: .init(coin: 200, knowledge: 30, lumber: 26),
            shape: BuildingShape(
                footprint: .init(2, 1),
                stories: [
                    .init(height: 22, inset: 0,
                          wallColor: Color(red: 0.42, green: 0.30, blue: 0.20),
                          trimColor: Color(red: 0.95, green: 0.85, blue: 0.42)),
                ],
                roof: .gable(ridgeAxis: .x, height: 14,
                             color: Color(red: 0.20, green: 0.40, blue: 0.20)),
                ornament: .chimney(side: .n, height: 8, color: trimDark),
                accent: nil
            ),
            glyph: "📚", blurb: "Bookbinder lives upstairs."
        ),
        Building(
            id: "forest-bridge", displayName: "Stone Bridge", biome: .forest,
            cost: .init(coin: 100, industry: 18, stability: 8),
            shape: BuildingShape(
                footprint: .init(2, 1),
                stories: [.init(height: 8, inset: 0,
                                wallColor: Color(red: 0.62, green: 0.62, blue: 0.55),
                                trimColor: trimDark)],
                roof: .hip(height: 6, color: Color(red: 0.55, green: 0.55, blue: 0.48)),
                ornament: nil, accent: nil
            ),
            glyph: "🌉", blurb: "Over the slowest part of the stream."
        ),
        Building(
            id: "forest-cabin", displayName: "Forest Cabin", biome: .forest,
            cost: .init(coin: 65, lumber: 16),
            shape: .cottage(
                wall: Color(red: 0.55, green: 0.36, blue: 0.22),
                roof: Color(red: 0.30, green: 0.45, blue: 0.30),
                trim: trimDark
            ),
            glyph: "🏕", blurb: "Pine planks, mossy roof.", isHome: true
        ),
    ]

    // MARK: - Beach (8)

    static let beach: [Building] = [
        Building(
            id: "beach-cottage", displayName: "Pastel Cottage", biome: .beach,
            cost: .init(coin: 50, lumber: 14),
            shape: .cottage(
                wall: Color(red: 0.95, green: 0.72, blue: 0.82),
                roof: Color(red: 0.42, green: 0.62, blue: 0.85),
                trim: .white,
                accent: .white
            ),
            glyph: "🏡", blurb: "Pale pink walls. Faded by salt.", isHome: true
        ),
        Building(
            id: "beach-lighthouse", displayName: "Lighthouse", biome: .beach,
            cost: .init(coin: 220, industry: 26, stability: 16),
            shape: .lighthouse(
                wall: .white,
                band: Color(red: 0.92, green: 0.42, blue: 0.42),
                capColor: Color(red: 0.30, green: 0.32, blue: 0.40)
            ),
            glyph: "🗼", blurb: "Sweeps every twelve seconds."
        ),
        Building(
            id: "beach-pier", displayName: "Pier", biome: .beach,
            cost: .init(coin: 90, lumber: 22, industry: 10),
            shape: BuildingShape(
                footprint: .init(2, 1),
                stories: [.init(height: 8, inset: 0,
                                wallColor: Color(red: 0.55, green: 0.42, blue: 0.30),
                                trimColor: trimDark)],
                roof: .flat,
                ornament: .spire(height: 12, color: trimDark),
                accent: nil
            ),
            glyph: "🛥", blurb: "Long boards. Long shadows at sunset."
        ),
        Building(
            id: "beach-icecream", displayName: "Ice Cream Stand", biome: .beach,
            cost: .init(coin: 70, industry: 6, growth: 6),
            shape: BuildingShape(
                footprint: .init(1, 1),
                stories: [.init(height: 12, inset: 0,
                                wallColor: Color(red: 0.95, green: 0.78, blue: 0.42),
                                trimColor: .white)],
                roof: .gable(ridgeAxis: .x, height: 8,
                             color: Color(red: 0.92, green: 0.42, blue: 0.42)),
                ornament: nil, accent: .white
            ),
            glyph: "🍦", blurb: "Open seasonally. Or whenever it feels open."
        ),
        Building(
            id: "beach-cafe", displayName: "Boardwalk Café", biome: .beach,
            cost: .init(coin: 110, lumber: 10, industry: 8, growth: 4),
            shape: .twoStory(
                wall: Color(red: 0.78, green: 0.55, blue: 0.42),
                upper: Color(red: 0.65, green: 0.42, blue: 0.30),
                roof: Color(red: 0.30, green: 0.32, blue: 0.40),
                trim: .white
            ),
            glyph: "☕", blurb: "Outdoor seating only."
        ),
        Building(
            id: "beach-aquarium", displayName: "Aquarium", biome: .beach,
            cost: .init(coin: 210, knowledge: 24, industry: 16, inspiration: 6),
            shape: .aquarium(
                wall: Color(red: 0.42, green: 0.62, blue: 0.92),
                capColor: Color(red: 0.30, green: 0.45, blue: 0.78)
            ),
            glyph: "🐠", blurb: "Children press their noses to the glass."
        ),
        Building(
            id: "beach-gardens", displayName: "Beach Gardens", biome: .beach,
            cost: .init(coin: 55, growth: 16),
            shape: .gardens(
                grass: Color(red: 0.55, green: 0.78, blue: 0.42),
                flower: Color(red: 0.94, green: 0.55, blue: 0.62)
            ),
            glyph: "🌺", blurb: "Hibiscus, sand grass, glass-bead paths."
        ),
        Building(
            id: "beach-shrine", displayName: "Sea Shrine", biome: .beach,
            cost: .init(coin: 130, lumber: 8, stability: 6, inspiration: 12),
            shape: .shrine(
                wall: Color(red: 0.92, green: 0.30, blue: 0.42),
                roof: Color(red: 0.55, green: 0.16, blue: 0.22)
            ),
            glyph: "⛩", blurb: "Bells, rope, salt-bleached wood."
        ),
        Building(
            id: "beach-bungalow", displayName: "Bungalow", biome: .beach,
            cost: .init(coin: 60, lumber: 14),
            shape: .cottage(
                wall: Color(red: 0.78, green: 0.92, blue: 0.92),
                roof: Color(red: 0.42, green: 0.62, blue: 0.78),
                trim: .white,
                accent: .white
            ),
            glyph: "🏝", blurb: "Wraparound porch, no shoes needed.", isHome: true
        ),
    ]
}

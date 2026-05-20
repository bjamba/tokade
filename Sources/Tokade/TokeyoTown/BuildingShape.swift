import SwiftUI

/// A composable recipe for procedurally drawing a building from iso prisms.
/// Each recipe is a stack of `Story` instances plus a roof, optional accent,
/// and optional ornament (chimney / spire / annex).
///
/// Drawn by `IsoTileRenderer` — no sprite assets required. Footprint is
/// in tiles; each story scales horizontally with the footprint.
struct BuildingShape: Hashable {
    /// Tiles wide × deep. Most buildings are 1×1; landmarks are 2×2.
    let footprint: Footprint
    let stories: [Story]
    let roof: Roof
    let ornament: Ornament?
    /// Optional shutter / door / window accent color for the front face.
    let accent: Color?
    /// Optional per-archetype extra detail drawn over the building —
    /// gives different building types visually distinct silhouettes.
    var detail: Detail?

    enum Detail: Hashable {
        /// Visible plank rows across the top face + posts dropping into
        /// the tile base. For piers, bridges, boardwalks.
        case planks(plankColor: Color, postColor: Color)
        /// Small dark window squares on the front faces. For cottages,
        /// row houses, lodges.
        case windows(rows: Int, columns: Int, color: Color)
        /// Crossed sails on top of the building. For windmills.
        case sails(color: Color)
        /// Bell shape suspended over the roof. For shrines.
        case bell(color: Color)
        /// A few thin horizontal slat lines on the wall. For ice fishing
        /// huts and other plank-sided buildings.
        case slats(color: Color)
    }

    struct Footprint: Hashable {
        let w: Int
        let h: Int
        init(_ w: Int, _ h: Int) {
            self.w = w; self.h = h
        }
    }

    struct Story: Hashable {
        /// Height in pixels. 18 is a "single story", 32 is a tall hall.
        let height: CGFloat
        /// Inset on each side (px). 0 = same footprint as base. Used to
        /// give upper floors a stepped look.
        let inset: CGFloat
        let wallColor: Color
        let trimColor: Color?
    }

    enum Roof: Hashable {
        /// Flat — just the top diamond of the topmost story.
        case flat
        /// Pitched two-plane roof. `ridgeAxis` is the long axis the ridge
        /// runs along (.x = east-west on screen, .y = north-south).
        case gable(ridgeAxis: Axis, height: CGFloat, color: Color)
        /// Pyramid / hip — four triangles meeting at an apex.
        case hip(height: CGFloat, color: Color)
        /// Dome — a flattened half-ellipse.
        case dome(height: CGFloat, color: Color)
        enum Axis: Hashable { case x, y }
    }

    enum Ornament: Hashable {
        case chimney(side: Side, height: CGFloat, color: Color)
        case spire(height: CGFloat, color: Color)        // for lighthouses, clock towers
        case annex(side: Side, depth: CGFloat, color: Color)  // small shed on one side
        enum Side: Hashable { case n, e, s, w }
    }

    static func cottage(wall: Color, roof: Color, trim: Color? = nil, accent: Color? = nil) -> BuildingShape {
        BuildingShape(
            footprint: .init(1, 1),
            stories: [.init(height: 18, inset: 0, wallColor: wall, trimColor: trim)],
            roof: .gable(ridgeAxis: .x, height: 12, color: roof),
            ornament: .chimney(side: .n, height: 8, color: trim ?? roof),
            accent: accent
        )
    }

    static func twoStory(wall: Color, upper: Color, roof: Color, trim: Color? = nil) -> BuildingShape {
        BuildingShape(
            footprint: .init(1, 1),
            stories: [
                .init(height: 18, inset: 0, wallColor: wall, trimColor: trim),
                .init(height: 14, inset: 4, wallColor: upper, trimColor: trim),
            ],
            roof: .gable(ridgeAxis: .y, height: 8, color: roof),
            ornament: nil,
            accent: nil
        )
    }

    static func dome(wall: Color, dome: Color, height: CGFloat = 14) -> BuildingShape {
        BuildingShape(
            footprint: .init(1, 1),
            stories: [.init(height: 18, inset: 0, wallColor: wall, trimColor: nil)],
            roof: .dome(height: height, color: dome),
            ornament: nil,
            accent: nil
        )
    }

    static func tower(wall: Color, capColor: Color) -> BuildingShape {
        BuildingShape(
            footprint: .init(1, 1),
            stories: [
                .init(height: 22, inset: 0, wallColor: wall, trimColor: capColor),
                .init(height: 16, inset: 4, wallColor: wall, trimColor: capColor),
            ],
            roof: .hip(height: 10, color: capColor),
            ornament: .spire(height: 12, color: capColor),
            accent: nil
        )
    }

    static func lighthouse(wall: Color, band: Color, capColor: Color) -> BuildingShape {
        // v3.3 — three stories that *narrow* as they rise (not widen),
        // for a slimmer, taller tower silhouette that doesn't dominate
        // neighbouring 1×1 buildings as much.
        BuildingShape(
            footprint: .init(1, 1),
            stories: [
                .init(height: 12, inset: 0, wallColor: wall, trimColor: band),
                .init(height: 12, inset: 5, wallColor: band, trimColor: wall),
                .init(height: 12, inset: 9, wallColor: wall, trimColor: band),
            ],
            roof: .hip(height: 6, color: capColor),
            ornament: .spire(height: 8, color: capColor),
            accent: nil
        )
    }

    static func park(grass: Color, accent: Color) -> BuildingShape {
        BuildingShape(
            footprint: .init(1, 1),
            stories: [.init(height: 4, inset: 0, wallColor: grass, trimColor: nil)],
            roof: .hip(height: 14, color: accent),
            ornament: nil,
            accent: nil
        )
    }

    static func pyramid(stone: Color, capColor: Color) -> BuildingShape {
        BuildingShape(
            footprint: .init(2, 2),
            stories: [
                .init(height: 12, inset: 0, wallColor: stone, trimColor: nil),
                .init(height: 12, inset: 6, wallColor: stone, trimColor: nil),
            ],
            roof: .hip(height: 16, color: capColor),
            ornament: nil,
            accent: nil
        )
    }

    static func bigHall(wall: Color, roof: Color, trim: Color? = nil) -> BuildingShape {
        BuildingShape(
            footprint: .init(2, 1),
            stories: [.init(height: 22, inset: 0, wallColor: wall, trimColor: trim)],
            roof: .gable(ridgeAxis: .x, height: 14, color: roof),
            ornament: nil,
            accent: nil
        )
    }

    static func aquarium(wall: Color, capColor: Color) -> BuildingShape {
        // v3.3 — rectangular tank, flat roof, porthole windows. The
        // earlier dome read as a body of water spilling out of the
        // building (especially in the beach biome).
        BuildingShape(
            footprint: .init(2, 2),
            stories: [.init(height: 22, inset: 0, wallColor: wall, trimColor: capColor)],
            roof: .flat,
            ornament: nil,
            accent: nil,
            detail: .windows(rows: 2, columns: 3, color: capColor)
        )
    }

    static func shrine(wall: Color, roof: Color) -> BuildingShape {
        BuildingShape(
            footprint: .init(1, 1),
            stories: [.init(height: 14, inset: 0, wallColor: wall, trimColor: nil)],
            roof: .gable(ridgeAxis: .x, height: 16, color: roof),
            ornament: .spire(height: 10, color: roof),
            accent: nil,
            detail: .bell(color: Color(red: 0.82, green: 0.65, blue: 0.30))
        )
    }

    static func windmill(wall: Color, sail: Color) -> BuildingShape {
        BuildingShape(
            footprint: .init(1, 1),
            stories: [
                .init(height: 14, inset: 0, wallColor: wall, trimColor: sail),
                .init(height: 10, inset: 3, wallColor: wall, trimColor: sail),
            ],
            roof: .hip(height: 10, color: sail),
            ornament: .spire(height: 8, color: sail),
            accent: nil
        )
    }

    static func gardens(grass: Color, flower: Color) -> BuildingShape {
        BuildingShape(
            footprint: .init(1, 1),
            stories: [.init(height: 3, inset: 0, wallColor: grass, trimColor: nil)],
            roof: .hip(height: 6, color: flower),
            ornament: nil,
            accent: nil
        )
    }

    static func waterFeature(stone: Color, water: Color) -> BuildingShape {
        BuildingShape(
            footprint: .init(1, 1),
            stories: [.init(height: 6, inset: 0, wallColor: stone, trimColor: nil)],
            roof: .dome(height: 8, color: water),
            ornament: nil,
            accent: nil
        )
    }
}

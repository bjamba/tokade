import SwiftUI

/// Visual + thematic per-biome data. Palette is the procedural-placeholder
/// color set used until we swap in Kenney/custom pixel art.
enum BiomeCatalog {
    struct BiomeInfo {
        let biome: TokeyoTownState.Biome
        let displayName: String
        let blurb: String
        let groundColor: Color
        let groundShadeColor: Color   // darker shade for the iso side faces
        let accentColor: Color        // vegetation / decor accent
        let waterColor: Color?        // nil for non-coastal biomes
    }

    static let all: [BiomeInfo] = [
        BiomeInfo(
            biome: .plain,
            displayName: "Plain",
            blurb: "Rolling pastures, neon trees, modern roads.",
            groundColor:      Color(red: 0.60, green: 0.78, blue: 0.42),
            groundShadeColor: Color(red: 0.45, green: 0.62, blue: 0.30),
            accentColor:      Color(red: 0.93, green: 0.78, blue: 0.36),
            waterColor:       nil
        ),
        BiomeInfo(
            biome: .desert,
            displayName: "Desert",
            blurb: "Wide sand flats, oases, sunset-colored stucco.",
            groundColor:      Color(red: 0.95, green: 0.81, blue: 0.55),
            groundShadeColor: Color(red: 0.78, green: 0.61, blue: 0.36),
            accentColor:      Color(red: 0.50, green: 0.74, blue: 0.45),
            waterColor:       Color(red: 0.45, green: 0.72, blue: 0.82)
        ),
        BiomeInfo(
            biome: .tundra,
            displayName: "Tundra",
            blurb: "Snowfields, pine groves, smoking stone chimneys.",
            groundColor:      Color(red: 0.92, green: 0.94, blue: 0.97),
            groundShadeColor: Color(red: 0.72, green: 0.78, blue: 0.84),
            accentColor:      Color(red: 0.32, green: 0.46, blue: 0.40),
            waterColor:       Color(red: 0.55, green: 0.74, blue: 0.84)
        ),
        BiomeInfo(
            biome: .forest,
            displayName: "Forest",
            blurb: "Mossy clearings, observatories, river stones.",
            groundColor:      Color(red: 0.32, green: 0.55, blue: 0.30),
            groundShadeColor: Color(red: 0.22, green: 0.40, blue: 0.22),
            accentColor:      Color(red: 0.86, green: 0.55, blue: 0.32),
            waterColor:       Color(red: 0.30, green: 0.55, blue: 0.62)
        ),
        BiomeInfo(
            biome: .beach,
            displayName: "Beach",
            blurb: "Coastal sand, pastel cottages, lazy boardwalks.",
            groundColor:      Color(red: 0.96, green: 0.88, blue: 0.62),
            groundShadeColor: Color(red: 0.82, green: 0.72, blue: 0.48),
            accentColor:      Color(red: 0.94, green: 0.55, blue: 0.62),
            waterColor:       Color(red: 0.35, green: 0.70, blue: 0.86)
        )
    ]

    static func info(_ b: TokeyoTownState.Biome) -> BiomeInfo {
        all.first(where: { $0.biome == b }) ?? all[0]
    }
}

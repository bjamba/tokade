import AppKit
import Foundation

/// Bundled pixel-art biome tiles per region flavor. Each tile is 32×32 and
/// gets rendered at the region's position on the overworld map.
enum BiomeArt {
    private static var cache: [Region.Flavor: SpriteMatrix?] = [:]

    static func tile(for flavor: Region.Flavor) -> SpriteMatrix? {
        if let cached = cache[flavor] { return cached }
        let name: String = switch flavor {
        case .stonework:     "biome-stonework"
        case .ironFortress:  "biome-iron-fortress"
        case .gardenVillage: "biome-garden-village"
        case .bazaar:        "biome-bazaar"
        case .openSteppe:    "biome-open-steppe"
        case .wilderness:    "biome-wilderness"
        }
        guard let url = appBundledResource(named: name, ext: "matrix"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let parsed = try? SpriteMatrix.parse(text) else {
            cache[flavor] = nil
            return nil
        }
        cache[flavor] = parsed
        return parsed
    }

    /// Per-flavor palette tuned to the biome's color story. Each role gets a
    /// flavor-appropriate hue so the bundled matrix (baked palette-neutral)
    /// renders with the right palette at runtime.
    static func palette(for flavor: Region.Flavor) -> Palette {
        switch flavor {
        case .stonework:
            return Palette.recolor(.boba, overrides: [
                .skin:       hex("#A0A0A0"), .skinLight: hex("#C0C0C0"), .skinDark: hex("#666666"),
                .hair:       hex("#8B6F47"), .hairDark:  hex("#5A4A2F"),
                .iris:       hex("#FFD060"),
                .shirt:      hex("#7CB893"), .shirtLight: hex("#B6E0C6"), .shirtDark: hex("#3F7C57"),
                .pants:      hex("#5A5560"), .pantsLight: hex("#8A8590"), .pantsDark: hex("#2A2530"),
            ])
        case .ironFortress:
            return Palette.recolor(.boba, overrides: [
                .skin:       hex("#888888"), .skinLight: hex("#A0A0A0"), .skinDark: hex("#555555"),
                .hair:       hex("#3D3030"), .hairDark:  hex("#1F1818"),
                .iris:       hex("#FFA040"),
                .shirt:      hex("#5C8060"), .shirtLight: hex("#88A088"), .shirtDark: hex("#2A4030"),
                .pants:      hex("#3A3030"), .pantsLight: hex("#5A4848"), .pantsDark: hex("#1A1018"),
            ])
        case .gardenVillage:
            return Palette.recolor(.boba, overrides: [
                .skin:       hex("#FFFFFF"), .skinLight: hex("#C5E8CC"), .skinDark: hex("#7AB590"),
                .hair:       hex("#E0C080"), .hairDark:  hex("#A07050"),
                .iris:       hex("#FF6688"),
                .shirt:      hex("#6FB85B"), .shirtLight: hex("#A0D880"), .shirtDark: hex("#3F6F33"),
                .pants:      hex("#5C4033"), .pantsLight: hex("#8B6840"), .pantsDark: hex("#3D2920"),
            ])
        case .bazaar:
            return Palette.recolor(.boba, overrides: [
                .skin:       hex("#D8C090"), .skinLight: hex("#E8D8B0"), .skinDark: hex("#A89060"),
                .hair:       hex("#E8D070"), .hairDark:  hex("#B89240"),
                .iris:       hex("#C04848"),
                .shirt:      hex("#D88040"), .shirtLight: hex("#E8A060"), .shirtDark: hex("#A85020"),
                .pants:      hex("#8B6F47"), .pantsLight: hex("#B89060"), .pantsDark: hex("#5A4030"),
            ])
        case .openSteppe:
            return Palette.recolor(.boba, overrides: [
                .skin:       hex("#E0D08C"), .skinLight: hex("#F0E8B0"), .skinDark: hex("#A89060"),
                .hair:       hex("#D0B870"), .hairDark:  hex("#A88840"),
                .iris:       hex("#FFA060"),
                .shirt:      hex("#7C9050"), .shirtLight: hex("#A0B470"), .shirtDark: hex("#506030"),
                .pants:      hex("#5C4033"), .pantsLight: hex("#8B6840"), .pantsDark: hex("#3D2920"),
            ])
        case .wilderness:
            return Palette.recolor(.boba, overrides: [
                .skin:       hex("#888888"), .skinLight: hex("#A0A0A0"), .skinDark: hex("#444444"),
                .hair:       hex("#8B6F47"), .hairDark:  hex("#5A4A2F"),
                .iris:       hex("#FF6020"),
                .shirt:      hex("#4A8050"), .shirtLight: hex("#6AA070"), .shirtDark: hex("#1A4020"),
                .pants:      hex("#5A4830"), .pantsLight: hex("#7A6850"), .pantsDark: hex("#2A1810"),
            ])
        }
    }

    private static func hex(_ s: String) -> NSColor {
        NSColor.fromHex(s) ?? .black
    }
}

import Foundation

/// Maps monster display names from the encounter rosters to their bundled
/// sprite asset (matrix filename without extension or `monster-` prefix).
/// Names not in this table render without a sprite (text-only enemy card).
enum MonsterArt {
    private static let nameMap: [String: String] = [
        "Stray Slime":     "stray-slime",
        "Lost Sprite":     "stray-slime",      // share for now
        "Granite Golem":   "granite-golem",
        "Loose Brick":     "granite-golem",
        "Compile Beetle":  "compile-beetle",
        "Iron Sentinel":   "compile-beetle",
        "Rust Imp":        "rust-imp",
        "Vine Snare":      "vine-snare",
        "Snail Sage":      "vine-snare",
        "Pickpocket":      "pickpocket",
        "Hawker":          "pickpocket",
        "Steppe Wolf":     "steppe-wolf",
        "Wind Wisp":       "steppe-wolf",      // share for now
    ]

    private static var cache: [String: SpriteMatrix?] = [:]

    /// Look up the sprite matrix for a monster display name. Returns nil if
    /// the monster has no bundled art (sprite-less monsters are fine — the
    /// UI falls back to text).
    static func sprite(for monsterName: String) -> SpriteMatrix? {
        if let cached = cache[monsterName] { return cached }
        guard let assetName = nameMap[monsterName] else {
            cache[monsterName] = nil
            return nil
        }
        let resourceName = "monster-\(assetName)"
        guard let url = appBundledResource(named: resourceName, ext: "matrix"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let parsed = try? SpriteMatrix.parse(text) else {
            cache[monsterName] = nil
            return nil
        }
        cache[monsterName] = parsed
        return parsed
    }

    /// Per-monster palette so each kind of monster has a visual identity
    /// rather than all of them showing in the Tokegotchi-default palette.
    static func palette(for monsterName: String) -> Palette {
        // Stones — grey / brown
        if monsterName.contains("Golem") || monsterName.contains("Brick") {
            return Palette.recolor(.boba, overrides: [
                .pants:      hex("#8A8A8A"),
                .pantsLight: hex("#B0B0B0"),
                .pantsDark:  hex("#555555"),
                .iris:       hex("#FFE060"),
            ])
        }
        // Metallic beetles — dark steel + green eyes
        if monsterName.contains("Beetle") || monsterName.contains("Sentinel") {
            return Palette.recolor(.boba, overrides: [
                .pants:      hex("#2A2A33"),
                .pantsLight: hex("#4A4A55"),
                .pantsDark:  hex("#15151A"),
                .iris:       hex("#33FF66"),
                .hair:       hex("#A88040"),
            ])
        }
        // Slimes — green
        if monsterName.contains("Slime") || monsterName.contains("Sprite") {
            return Palette.recolor(.boba, overrides: [
                .shirt:      hex("#56B250"),
                .shirtLight: hex("#88D080"),
                .shirtDark:  hex("#2A6A20"),
            ])
        }
        // Plant — fresh greens
        if monsterName.contains("Vine") || monsterName.contains("Snail") {
            return Palette.recolor(.boba, overrides: [
                .shirt:      hex("#3A8A40"),
                .shirtLight: hex("#7AC080"),
                .shirtDark:  hex("#1A4020"),
                .iris:       hex("#FFC050"),
            ])
        }
        // Pickpocket / Hawker — dark cloak
        if monsterName.contains("Pickpocket") || monsterName.contains("Hawker") {
            return Palette.recolor(.boba, overrides: [
                .pants:      hex("#3A2A40"),
                .pantsLight: hex("#5A405A"),
                .pantsDark:  hex("#1A0A20"),
                .iris:       hex("#FFA040"),
                .hair:       hex("#D4A93C"),    // gold coin
                .belt:       hex("#7A5A1A"),
            ])
        }
        // Wolves / wisps — slate grey
        if monsterName.contains("Wolf") || monsterName.contains("Wisp") {
            return Palette.recolor(.boba, overrides: [
                .pants:      hex("#5A5A6A"),
                .pantsLight: hex("#8080A0"),
                .pantsDark:  hex("#2A2A3A"),
                .iris:       hex("#FF8040"),
            ])
        }
        // Rust imps — rusty brown
        if monsterName.contains("Imp") {
            return Palette.recolor(.boba, overrides: [
                .belt:       hex("#8B5A2B"),
                .hair:       hex("#E68040"),
                .iris:       hex("#FFE060"),
            ])
        }
        return .boba
    }

    private static func hex(_ s: String) -> NSColor { NSColor.fromHex(s) ?? .black }
}

import AppKit

extension Palette {
    /// Return a new palette with selected roles overridden.
    static func recolor(_ base: Palette, overrides: [PaletteRole: NSColor]) -> Palette {
        var colors = base.colors
        for (role, color) in overrides { colors[role] = color }
        return Palette(colors: colors)
    }
}

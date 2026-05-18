import AppKit
import Foundation

/// Bundled overworld map matrix + palette. Used as the background of the
/// map screen so the player sees the full pixel-art world, not a blank
/// parchment.
enum WorldMapArt {
    static let tile: SpriteMatrix? = {
        guard let url = appBundledResource(named: "world-overworld", ext: "matrix"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return try? SpriteMatrix.parse(text)
    }()

    /// Custom palette that maps the world map's baked role glyphs back to
    /// terrain-appropriate colors:
    /// - IRIS (ocean)
    /// - HAIR (continent base, sandy)
    /// - SHIRT (plains, grass-green)
    /// - SHIRT_DARK (forest)
    /// - PANTS / PANTS_DARK (mountains)
    /// - SKIN_DARK (desert)
    static let palette: Palette? = Palette.recolor(.boba, overrides: [
        .iris:       hex("#3088C0"),    // ocean / lake / river
        .skin:       hex("#E8D8B0"),    // beach (light tan)
        .skinLight:  hex("#F0E8C0"),    // beach (lighter)
        .skinDark:   hex("#D8B870"),    // desert sand
        .hair:       hex("#C9B89E"),    // continent base (warm tan)
        .hairDark:   hex("#9C8870"),    // shadowed land
        .shirt:      hex("#5BA050"),    // plains
        .shirtLight: hex("#8FCE7C"),    // plains highlight
        .shirtDark:  hex("#2F6634"),    // forest
        .pants:      hex("#7B6450"),    // mountain mid
        .pantsLight: hex("#A88A6E"),    // mountain light
        .pantsDark:  hex("#4A3828"),    // mountain dark
        .belt:       hex("#8B6F47"),    // earth
        .white:      hex("#FFFFFF"),    // snow caps
    ])

    private static func hex(_ s: String) -> NSColor {
        NSColor.fromHex(s) ?? .black
    }
}

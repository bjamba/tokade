import AppKit
import Foundation

/// Pixel-art banner art for each game shown in the Games launcher.
enum GameBanner {
    static func sprite(for gameId: String) -> SpriteMatrix? {
        let name = "banner-\(gameId)"
        guard let url = appBundledResource(named: name, ext: "matrix"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return try? SpriteMatrix.parse(text)
    }

    static func palette(for gameId: String) -> Palette {
        switch gameId {
        case "token-gaiden-rpg":
            return Palette.recolor(.boba, overrides: [
                .iris:       hex("#3088C0"),
                .hair:       hex("#FFD060"),
                .hairDark:   hex("#A88840"),
                .shirt:      hex("#5BA050"),
                .shirtDark:  hex("#2F6634"),
                .pants:      hex("#7B6450"),
                .pantsDark:  hex("#4A3828"),
                .skin:       hex("#C7A5D9"),
                .skinDark:   hex("#A07AB8"),
            ])
        default:
            return .boba
        }
    }

    private static func hex(_ s: String) -> NSColor {
        NSColor.fromHex(s) ?? .black
    }
}

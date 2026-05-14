import AppKit

/// Roles in a sprite matrix. The matrix glyph identifies which role each pixel
/// belongs to; the active `Palette` decides the RGB at render time. This is
/// what lets one matrix render as 1,000s of distinct Tokegotchis.
enum PaletteRole: CaseIterable {
    case transparent
    case outline
    case skin
    case skinLight
    case skinDark
    case hair
    case hairDark
    case iris
    case white
    case shirt
    case shirtLight
    case shirtDark
    case pants
    case pantsLight
    case pantsDark
    case belt

    /// Glyph used in the matrix text file.
    var glyph: Character {
        switch self {
        case .transparent: return "."
        case .outline:     return "1"
        case .skin:        return "2"
        case .skinLight:   return "3"
        case .skinDark:    return "4"
        case .hair:        return "5"
        case .hairDark:    return "6"
        case .iris:        return "7"
        case .white:       return "8"
        case .shirt:       return "9"
        case .shirtLight:  return "A"
        case .shirtDark:   return "B"
        case .pants:       return "C"
        case .pantsLight:  return "D"
        case .pantsDark:   return "E"
        case .belt:        return "F"
        }
    }
}

/// Concrete RGB choice for each role. Built from a Tokegotchi's appearance
/// + equipped clothing. See `Palette.boba` for the default starter.
struct Palette: Equatable {
    var colors: [PaletteRole: NSColor]

    /// Resolve a single matrix glyph to its NSColor, or nil for transparent.
    func color(forGlyph glyph: Character) -> NSColor? {
        for role in PaletteRole.allCases where role.glyph == glyph {
            if role == .transparent { return nil }
            return colors[role]
        }
        return nil
    }

    /// Default "Boba" preset — the starter Tokegotchi the design folder bakes.
    static let boba = Palette(colors: [
        .outline:     NSColor(srgbRed: 0x1A / 255, green: 0x1A / 255, blue: 0x2E / 255, alpha: 1),
        .skin:        NSColor(srgbRed: 0xC7 / 255, green: 0xA5 / 255, blue: 0xD9 / 255, alpha: 1),
        .skinLight:   NSColor(srgbRed: 0xDB / 255, green: 0xC1 / 255, blue: 0xE8 / 255, alpha: 1),
        .skinDark:    NSColor(srgbRed: 0xA0 / 255, green: 0x7A / 255, blue: 0xB8 / 255, alpha: 1),
        .hair:        NSColor(srgbRed: 0xE8 / 255, green: 0xDC / 255, blue: 0xC4 / 255, alpha: 1),
        .hairDark:    NSColor(srgbRed: 0xA8 / 255, green: 0x94 / 255, blue: 0x73 / 255, alpha: 1),
        .iris:        NSColor(srgbRed: 0x4A / 255, green: 0x7B / 255, blue: 0xC5 / 255, alpha: 1),
        .white:       NSColor.white,
        .shirt:       NSColor(srgbRed: 0x5A / 255, green: 0x7F / 255, blue: 0x3F / 255, alpha: 1),
        .shirtLight:  NSColor(srgbRed: 0x7D / 255, green: 0xA0 / 255, blue: 0x55 / 255, alpha: 1),
        .shirtDark:   NSColor(srgbRed: 0x3F / 255, green: 0x5A / 255, blue: 0x2A / 255, alpha: 1),
        .pants:       NSColor(srgbRed: 0x5C / 255, green: 0x40 / 255, blue: 0x33 / 255, alpha: 1),
        .pantsLight:  NSColor(srgbRed: 0x7C / 255, green: 0x5C / 255, blue: 0x45 / 255, alpha: 1),
        .pantsDark:   NSColor(srgbRed: 0x3D / 255, green: 0x29 / 255, blue: 0x20 / 255, alpha: 1),
        .belt:        NSColor(srgbRed: 0x8B / 255, green: 0x6F / 255, blue: 0x47 / 255, alpha: 1),
    ])
}

/// Curated swatches for the character creator. Stored as hex so we can
/// surface them in UI without losing brand consistency.
enum CharacterCreatorSwatches {
    static let skin: [(name: String, mid: String, light: String, dark: String)] = [
        ("lavender", "#C7A5D9", "#DBC1E8", "#A07AB8"),
        ("peach",    "#E5A88E", "#F0C0A8", "#B8826A"),
        ("sage",     "#A5D9B5", "#C5E8CC", "#7AB590"),
        ("sand",     "#DDC893", "#ECDDB5", "#B89E5C"),
        ("slate",    "#A8B5C7", "#C5CFDB", "#7E8AA0"),
        ("coral",    "#E89C9C", "#F2B8B8", "#B86E6E"),
    ]

    static let iris: [(name: String, hex: String)] = [
        ("blue",   "#4A7BC5"),
        ("brown",  "#8B5A3C"),
        ("green",  "#3FA060"),
        ("amber",  "#D4A93C"),
        ("violet", "#9A4FC0"),
        ("grey",   "#7E8AA0"),
    ]

    static let hair: [(name: String, hex: String, darkHex: String)] = [
        ("ivory",   "#E8DCC4", "#A89473"),
        ("coral",   "#D97757", "#9A4A36"),
        ("black",   "#2A2A3A", "#1A1A2A"),
        ("blonde",  "#E8D070", "#A89240"),
        ("silver",  "#D0D5DA", "#8A9098"),
        ("magenta", "#D04AAF", "#883878"),
    ]

    static let hairStyles: [String] = [
        "horns", "spiky", "cat-ears", "pigtails", "mohawk",
        "antennae", "long", "bald", "flame", "tentacles", "mushroom"
    ]
}

extension NSColor {
    /// Parse "#RRGGBB" → sRGB NSColor. Returns nil for malformed input.
    static func fromHex(_ s: String) -> NSColor? {
        var t = s
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8)  & 0xFF) / 255
        let b = CGFloat(v        & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

import AppKit
import CoreGraphics

/// CRT styling options applied at render time. Each is a different look
/// applied over the upscaled pixel art.
enum CRTMode: String, CaseIterable, Identifiable, Codable {
    case off
    case scanlines   // alternate source-pixel rows darkened (subtle stripes)
    case phosphor    // right + bottom edge of every source pixel darkened (grid)
    case soft        // bell-curve brightness per source-pixel row (smooth)
    case dotMatrix   // bottom-right corner of every cell darkened (LED feel)
    case fade        // edges of each source pixel slightly darker (puffy)

    var id: String { rawValue }
    var label: String {
        switch self {
        case .off:       return "Off"
        case .scanlines: return "Scanlines"
        case .phosphor:  return "Phosphor grid"
        case .soft:      return "Soft glow"
        case .dotMatrix: return "Dot matrix"
        case .fade:      return "Edge fade"
        }
    }
}

/// Rasterizes a sprite matrix to an NSImage at a given upscale factor, using a
/// palette to resolve each role glyph to a concrete RGB.
///
/// We use Core Graphics with `interpolationQuality = .none` to preserve the
/// chunky pixel-art look at any scale.
enum SpriteRenderer {
    /// Render `matrix` at integer upscale `scale` using `palette` with an
    /// optional CRT post-effect baked into the per-cell paint.
    static func render(_ matrix: SpriteMatrix, palette: Palette, scale: Int = 8, crt: CRTMode = .off) -> NSImage {
        let w = matrix.width * scale
        let h = matrix.height * scale
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bm = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: bm
        ) else {
            return NSImage(size: NSSize(width: w, height: h))
        }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)

        // CoreGraphics y is bottom-up — paint from the matrix's top row to the
        // upscaled bitmap's top row by flipping the y-coordinate.
        for (rowIdx, row) in matrix.rows.enumerated() {
            for (colIdx, glyph) in row.enumerated() {
                guard let nsColor = palette.color(forGlyph: glyph),
                      let resolved = nsColor.usingColorSpace(.sRGB) else { continue }
                let yFromBottom = matrix.height - 1 - rowIdx
                paintCell(
                    ctx: ctx,
                    color: resolved,
                    x: colIdx * scale,
                    y: yFromBottom * scale,
                    size: scale,
                    isAlternateRow: rowIdx % 2 == 1,
                    crt: crt
                )
            }
        }

        guard let img = ctx.makeImage() else {
            return NSImage(size: NSSize(width: w, height: h))
        }
        return NSImage(cgImage: img, size: NSSize(width: w, height: h))
    }

    /// Paint one source pixel (a `size x size` block) with CRT post-effects.
    private static func paintCell(
        ctx: CGContext,
        color: NSColor,
        x: Int, y: Int, size: Int,
        isAlternateRow: Bool,
        crt: CRTMode
    ) {
        // Always paint the base block first.
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: x, y: y, width: size, height: size))

        switch crt {
        case .off:
            return

        case .scanlines:
            // Darken every other source-pixel row entirely.
            guard isAlternateRow else { return }
            ctx.setFillColor(darken(color, factor: 0.78).cgColor)
            ctx.fill(CGRect(x: x, y: y, width: size, height: size))

        case .phosphor:
            // Right column + bottom row of each source pixel darkened — grid feel.
            let line = max(1, size / 8)
            let dark = darken(color, factor: 0.65).cgColor
            ctx.setFillColor(dark)
            ctx.fill(CGRect(x: x + size - line, y: y, width: line, height: size))
            ctx.fill(CGRect(x: x, y: y, width: size, height: line))

        case .soft:
            // Bell-curve: bottom of cell darker, top brighter — like CRT phosphor decay.
            let band = max(1, size / 4)
            let dim  = darken(color, factor: 0.72).cgColor
            let lit  = lighten(color, factor: 1.10).cgColor
            ctx.setFillColor(dim)
            ctx.fill(CGRect(x: x, y: y, width: size, height: band))
            ctx.setFillColor(lit)
            ctx.fill(CGRect(x: x, y: y + size - band, width: size, height: band))

        case .dotMatrix:
            // Tiny dark square in bottom-right — LED-display feel.
            let dot = max(1, size / 3)
            ctx.setFillColor(darken(color, factor: 0.55).cgColor)
            ctx.fill(CGRect(x: x + size - dot, y: y, width: dot, height: dot))

        case .fade:
            // 1-pixel dark frame around the cell — gives each pixel a puffy look.
            let f = max(1, size / 10)
            ctx.setFillColor(darken(color, factor: 0.72).cgColor)
            ctx.fill(CGRect(x: x, y: y, width: size, height: f))                            // bottom
            ctx.fill(CGRect(x: x, y: y + size - f, width: size, height: f))                 // top
            ctx.fill(CGRect(x: x, y: y, width: f, height: size))                            // left
            ctx.fill(CGRect(x: x + size - f, y: y, width: f, height: size))                 // right
        }
    }

    private static func darken(_ c: NSColor, factor: CGFloat) -> NSColor {
        NSColor(
            srgbRed: c.redComponent * factor,
            green: c.greenComponent * factor,
            blue: c.blueComponent * factor,
            alpha: c.alphaComponent
        )
    }

    private static func lighten(_ c: NSColor, factor: CGFloat) -> NSColor {
        NSColor(
            srgbRed: min(1, c.redComponent * factor),
            green: min(1, c.greenComponent * factor),
            blue: min(1, c.blueComponent * factor),
            alpha: c.alphaComponent
        )
    }
}

import AppKit
import CoreGraphics

/// Rasterizes a sprite matrix to an NSImage at a given upscale factor, using a
/// palette to resolve each role glyph to a concrete RGB.
///
/// We use Core Graphics with `interpolationQuality = .none` to preserve the
/// chunky pixel-art look at any scale.
enum SpriteRenderer {
    /// Render `matrix` at integer upscale `scale` using `palette`. Each matrix
    /// cell becomes a `scale × scale` block. Transparent cells are not drawn.
    static func render(_ matrix: SpriteMatrix, palette: Palette, scale: Int = 8) -> NSImage {
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
                ctx.setFillColor(resolved.cgColor)
                let yFromBottom = matrix.height - 1 - rowIdx
                ctx.fill(CGRect(
                    x: colIdx * scale,
                    y: yFromBottom * scale,
                    width: scale,
                    height: scale
                ))
            }
        }

        guard let img = ctx.makeImage() else {
            return NSImage(size: NSSize(width: w, height: h))
        }
        return NSImage(cgImage: img, size: NSSize(width: w, height: h))
    }
}

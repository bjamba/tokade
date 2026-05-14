import Foundation

/// Layers cosmetic sprite matrices over a base matrix to produce the final
/// outfit. All inputs must have the same dimensions — both the base and every
/// cosmetic were baked from the same 32×54 viewBox at design time. See
/// ADR-0005.
enum SpriteComposer {
    /// Z-order is the array order — earliest in the layers array paints first
    /// (lowest). Transparent cells in a layer let earlier layers show through.
    static func compose(base: SpriteMatrix, layers: [SpriteMatrix]) -> SpriteMatrix {
        guard !layers.isEmpty else { return base }
        var rows = base.rows
        for layer in layers {
            // Skip a layer whose dimensions don't match; better to silently
            // drop a misshapen cosmetic than to crash the panel.
            guard layer.width == base.width, layer.height == base.height else { continue }
            for y in 0..<base.height {
                for x in 0..<base.width {
                    let g = layer.rows[y][x]
                    if g != "." {
                        rows[y][x] = g
                    }
                }
            }
        }
        return SpriteMatrix(width: base.width, height: base.height, rows: rows)
    }

    /// Layer order matches the design-doc z-order: cape (back) → legs/pants →
    /// arms → torso/shirt → belt → head/hair → eyewear → hat → held items.
    /// Caller passes whichever subset they have; the order is preserved.
    static func compose(base: SpriteMatrix, orderedLayers: [SpriteMatrix?]) -> SpriteMatrix {
        compose(base: base, layers: orderedLayers.compactMap { $0 })
    }
}

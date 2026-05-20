import SwiftUI

/// Coordinate math for the isometric grid. Tile (x, y) on an `N×N` board
/// projects to screen using a classic 2:1 iso ratio.
enum IsoMath {
    static let tileWidth: CGFloat = 32   // half-width of a tile diamond
    static let tileHeight: CGFloat = 16  // half-height
    static let buildingHeight: CGFloat = 18

    /// Project a tile (or sub-tile, for animated townsfolk) to its center
    /// point on the canvas, given the canvas size and the map's tile count.
    static func project(x: Double, y: Double, mapSize: Int, canvas: CGSize) -> CGPoint {
        let originX = canvas.width / 2
        let originY = canvas.height / 2 - CGFloat(mapSize) * tileHeight / 2
        let sx = (x - y) * tileWidth + originX
        let sy = (x + y) * tileHeight + originY
        return CGPoint(x: sx, y: sy)
    }

    /// Inverse — for click-to-place. Returns nil if outside the board.
    static func unproject(_ p: CGPoint, mapSize: Int, canvas: CGSize) -> (x: Int, y: Int)? {
        let originX = canvas.width / 2
        let originY = canvas.height / 2 - CGFloat(mapSize) * tileHeight / 2
        let dx = p.x - originX
        let dy = p.y - originY
        let fx = (dx / tileWidth + dy / tileHeight) / 2
        let fy = (dy / tileHeight - dx / tileWidth) / 2
        let ix = Int(fx.rounded(.down))
        let iy = Int(fy.rounded(.down))
        guard (0..<mapSize).contains(ix), (0..<mapSize).contains(iy) else { return nil }
        return (ix, iy)
    }
}

/// Procedural isometric tile renderer using SwiftUI's `Canvas`. Buildings
/// are drawn as extruded diamonds with a glyph label; townsfolk as small
/// hue-tinted circles. Designed to be replaced by a sprite-backed renderer
/// (Kenney.nl) without changing the surrounding code.
struct IsoTileRenderer: View {
    let state: TokeyoTownState
    /// Continuous tick value in [0, 1) used for sub-tile interpolation.
    let phase: Double
    /// Pending-placement preview building (drawn translucent at hovered tile).
    let placementPreview: (kind: String, tile: (Int, Int))?

    var body: some View {
        Canvas { context, size in
            let biome = BiomeCatalog.info(state.repo.biome)
            // Background sky/water
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(skyColor(for: biome))
            )

            // Ground tiles
            for y in 0..<state.repo.mapSize {
                for x in 0..<state.repo.mapSize {
                    drawGroundTile(context: context, x: x, y: y, biome: biome,
                                   canvas: size, lushness: state.repo.lushness)
                }
            }

            // Buildings — back-to-front by tile sum so further ones draw first
            let buildings = state.buildings.sorted {
                ($0.tileX + $0.tileY) < ($1.tileX + $1.tileY)
            }
            for placed in buildings {
                drawBuilding(context: context,
                             kind: placed.kind,
                             x: placed.tileX,
                             y: placed.tileY,
                             canvas: size,
                             translucent: false)
            }

            // Placement preview
            if let preview = placementPreview {
                drawBuilding(context: context,
                             kind: preview.kind,
                             x: preview.tile.0,
                             y: preview.tile.1,
                             canvas: size,
                             translucent: true)
            }

            // Townsfolk
            for npc in state.townsfolk {
                let dx = Double(npc.goalX) - npc.tileX
                let dy = Double(npc.goalY) - npc.tileY
                let interpX = npc.tileX + dx * phase
                let interpY = npc.tileY + dy * phase
                drawTownsfolk(context: context, x: interpX, y: interpY, hue: npc.hue, canvas: size)
            }
        }
    }

    // MARK: - Tile primitives

    private func drawGroundTile(
        context: GraphicsContext,
        x: Int,
        y: Int,
        biome: BiomeCatalog.BiomeInfo,
        canvas: CGSize,
        lushness: Double
    ) {
        let center = IsoMath.project(x: Double(x), y: Double(y),
                                     mapSize: state.repo.mapSize, canvas: canvas)
        let tw = IsoMath.tileWidth
        let th = IsoMath.tileHeight

        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - th))
        path.addLine(to: CGPoint(x: center.x + tw, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + th))
        path.addLine(to: CGPoint(x: center.x - tw, y: center.y))
        path.closeSubpath()

        // Mix the biome ground with a darker shade when lushness is low.
        let blend = biome.groundColor.opacity(lushness * 0.7 + 0.3)
        context.fill(path, with: .color(blend))
        context.stroke(path, with: .color(biome.groundShadeColor.opacity(0.5)), lineWidth: 0.5)
    }

    private func drawBuilding(
        context: GraphicsContext,
        kind: String,
        x: Int,
        y: Int,
        canvas: CGSize,
        translucent: Bool
    ) {
        guard let b = BuildingCatalog.find(kind) else { return }
        let center = IsoMath.project(x: Double(x), y: Double(y),
                                     mapSize: state.repo.mapSize, canvas: canvas)
        let tw = IsoMath.tileWidth * 0.78
        let th = IsoMath.tileHeight * 0.78
        let h: CGFloat = IsoMath.buildingHeight

        let top    = CGPoint(x: center.x,      y: center.y - th - h)
        let right  = CGPoint(x: center.x + tw, y: center.y - h)
        let bottom = CGPoint(x: center.x,      y: center.y + th - h)
        let left   = CGPoint(x: center.x - tw, y: center.y - h)
        let baseL  = CGPoint(x: center.x - tw, y: center.y)
        let baseR  = CGPoint(x: center.x + tw, y: center.y)
        let baseB  = CGPoint(x: center.x,      y: center.y + th)

        // Right face
        var rightFace = Path()
        rightFace.move(to: right)
        rightFace.addLine(to: bottom)
        rightFace.addLine(to: baseB)
        rightFace.addLine(to: baseR)
        rightFace.closeSubpath()
        // Left face
        var leftFace = Path()
        leftFace.move(to: left)
        leftFace.addLine(to: bottom)
        leftFace.addLine(to: baseB)
        leftFace.addLine(to: baseL)
        leftFace.closeSubpath()
        // Top diamond
        var topFace = Path()
        topFace.move(to: top)
        topFace.addLine(to: right)
        topFace.addLine(to: bottom)
        topFace.addLine(to: left)
        topFace.closeSubpath()

        let alpha = translucent ? 0.5 : 1.0
        context.fill(rightFace, with: .color(b.color.opacity(alpha * 0.78)))
        context.fill(leftFace,  with: .color(b.color.opacity(alpha * 0.92)))
        context.fill(topFace,   with: .color(b.color.opacity(alpha)))

        // Glyph
        let glyphResolved = context.resolve(
            Text(b.glyph)
                .font(.system(size: 14))
        )
        let glyphPoint = CGPoint(x: center.x, y: center.y - h - 2)
        context.draw(glyphResolved, at: glyphPoint, anchor: .center)
    }

    private func drawTownsfolk(
        context: GraphicsContext,
        x: Double,
        y: Double,
        hue: Double,
        canvas: CGSize
    ) {
        let center = IsoMath.project(x: x, y: y, mapSize: state.repo.mapSize, canvas: canvas)
        let r: CGFloat = 3
        let rect = CGRect(x: center.x - r, y: center.y - r - 4, width: r * 2, height: r * 2)
        let color = Color(hue: hue, saturation: 0.72, brightness: 0.92)
        context.fill(Path(ellipseIn: rect), with: .color(color))
        context.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.5)), lineWidth: 0.5)
    }

    private func skyColor(for biome: BiomeCatalog.BiomeInfo) -> Color {
        switch biome.biome {
        case .plain:  return Color(red: 0.78, green: 0.88, blue: 0.96)
        case .desert: return Color(red: 0.98, green: 0.85, blue: 0.62)
        case .tundra: return Color(red: 0.72, green: 0.84, blue: 0.92)
        case .forest: return Color(red: 0.45, green: 0.62, blue: 0.55)
        case .beach:  return Color(red: 0.55, green: 0.82, blue: 0.95)
        }
    }
}

import SwiftUI

/// Coordinate math for the isometric grid. Tile (x, y) on an `N×N` board
/// projects to screen using a classic 2:1 iso ratio.
enum IsoMath {
    /// v2 — tiles are larger so individual buildings are legible. The
    /// renderer also shrinks tile size for larger maps so a 48-tile town
    /// still fits comfortably in the panel.
    static let baseTileWidth: CGFloat = 28
    static let baseTileHeight: CGFloat = 14

    /// Effective half-width given a map size. Smaller maps get bigger
    /// tiles so the canvas is filled.
    static func tileWidth(forMapSize size: Int) -> CGFloat {
        switch size {
        case ..<14: return baseTileWidth + 6
        case 14..<20: return baseTileWidth + 2
        case 20..<32: return baseTileWidth
        default: return baseTileWidth - 4
        }
    }

    static func tileHeight(forMapSize size: Int) -> CGFloat {
        tileWidth(forMapSize: size) / 2
    }

    /// Project a tile (or sub-tile, for animated townsfolk) to its center
    /// point on the canvas, given the canvas size and the map's tile count.
    static func project(x: Double, y: Double, mapSize: Int, canvas: CGSize) -> CGPoint {
        let tw = tileWidth(forMapSize: mapSize)
        let th = tileHeight(forMapSize: mapSize)
        let originX = canvas.width / 2
        let originY = canvas.height / 2 - CGFloat(mapSize) * th / 2
        let sx = (x - y) * tw + originX
        let sy = (x + y) * th + originY
        return CGPoint(x: sx, y: sy)
    }

    /// Inverse — for click-to-place. Returns nil if outside the board.
    static func unproject(_ p: CGPoint, mapSize: Int, canvas: CGSize) -> (x: Int, y: Int)? {
        let tw = tileWidth(forMapSize: mapSize)
        let th = tileHeight(forMapSize: mapSize)
        let originX = canvas.width / 2
        let originY = canvas.height / 2 - CGFloat(mapSize) * th / 2
        let dx = p.x - originX
        let dy = p.y - originY
        let fx = (dx / tw + dy / th) / 2
        let fy = (dy / th - dx / tw) / 2
        let ix = Int(fx.rounded(.down))
        let iy = Int(fy.rounded(.down))
        guard (0..<mapSize).contains(ix), (0..<mapSize).contains(iy) else { return nil }
        return (ix, iy)
    }
}

/// Procedural isometric tile renderer. v2 adds:
///   - terrain layer (water/sand/grass/rock/tree/flower/road/decor)
///   - composable building shapes (no glyph on the world)
///   - per-tile decoration via the same draw routines
///   - hovered-tile placement preview honoring footprint
struct IsoTileRenderer: View {
    let state: TokeyoTownState
    /// Continuous tick value in [0, 1) used for sub-tile interpolation.
    let phase: Double
    /// Pending-placement preview building (drawn translucent at hovered tile).
    let placementPreview: PlacementPreview?

    struct PlacementPreview {
        let kind: String
        let tile: (x: Int, y: Int)
        let valid: Bool
    }

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
                    drawGroundTile(context: context, x: x, y: y, biome: biome, canvas: size)
                }
            }

            // Terrain decor (trees, flowers, rocks) — drawn back-to-front
            for y in 0..<state.repo.mapSize {
                for x in 0..<state.repo.mapSize {
                    drawTerrainDecor(context: context, x: x, y: y, biome: biome, canvas: size)
                }
            }

            // Buildings — back-to-front by tile sum so further ones draw first.
            // Include the footprint anchor (top-most/back-most tile).
            let buildings = state.buildings.sorted {
                ($0.tileX + $0.tileY) < ($1.tileX + $1.tileY)
            }
            for placed in buildings {
                if let b = BuildingCatalog.find(placed.kind) {
                    drawBuilding(context: context, building: b,
                                 anchorX: placed.tileX, anchorY: placed.tileY,
                                 canvas: size, alpha: 1.0)
                }
            }

            // Placement preview
            if let preview = placementPreview, let b = BuildingCatalog.find(preview.kind) {
                let alpha = preview.valid ? 0.55 : 0.25
                drawBuilding(context: context, building: b,
                             anchorX: preview.tile.x, anchorY: preview.tile.y,
                             canvas: size, alpha: alpha)
                // Red overlay outline when invalid
                if !preview.valid {
                    drawInvalidOverlay(context: context, building: b,
                                       anchorX: preview.tile.x, anchorY: preview.tile.y,
                                       canvas: size)
                }
            }

            // Townsfolk
            for npc in state.townsfolk {
                let goalDelta = (Double(npc.goalX) - npc.tileX, Double(npc.goalY) - npc.tileY)
                let interpX = npc.tileX + goalDelta.0 * phase
                let interpY = npc.tileY + goalDelta.1 * phase
                drawTownsfolk(context: context, x: interpX, y: interpY,
                              hue: npc.hue, canvas: size)
            }
        }
    }

    // MARK: - Ground

    private func drawGroundTile(
        context: GraphicsContext,
        x: Int,
        y: Int,
        biome: BiomeCatalog.BiomeInfo,
        canvas: CGSize
    ) {
        let tile = state.terrain.tile(x: x, y: y)
        let center = IsoMath.project(x: Double(x), y: Double(y),
                                     mapSize: state.repo.mapSize, canvas: canvas)
        let tw = IsoMath.tileWidth(forMapSize: state.repo.mapSize)
        let th = IsoMath.tileHeight(forMapSize: state.repo.mapSize)

        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - th))
        path.addLine(to: CGPoint(x: center.x + tw, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + th))
        path.addLine(to: CGPoint(x: center.x - tw, y: center.y))
        path.closeSubpath()

        let fill = groundColor(for: tile, biome: biome)
        context.fill(path, with: .color(fill))
        // Subtle grid line keeps tiles legible.
        context.stroke(path, with: .color(biome.groundShadeColor.opacity(0.35)), lineWidth: 0.5)
    }

    private func groundColor(for tile: TerrainTile, biome: BiomeCatalog.BiomeInfo) -> Color {
        let lush = state.repo.lushness
        switch tile {
        case .water:
            return biome.waterColor ?? Color(red: 0.30, green: 0.55, blue: 0.80)
        case .sand:
            return biome.biome == .desert
                ? biome.groundColor
                : Color(red: 0.96, green: 0.88, blue: 0.62)
        case .grass:
            // Mix toward the biome's shade color when lushness is low.
            return biome.groundColor.opacity(lush * 0.5 + 0.5)
        case .rock:
            return Color(red: 0.55, green: 0.55, blue: 0.55)
        case .tree, .flower, .decor:
            // Decor sits on grass/sand — render the grass/sand tile underneath.
            return biome.groundColor.opacity(lush * 0.5 + 0.5)
        case .road:
            return roadColor(for: biome)
        }
    }

    private func roadColor(for biome: BiomeCatalog.BiomeInfo) -> Color {
        switch biome.biome {
        case .plain, .desert: return Color(red: 0.72, green: 0.62, blue: 0.42)
        case .tundra, .forest: return Color(red: 0.55, green: 0.55, blue: 0.55)
        case .beach: return Color(red: 0.78, green: 0.62, blue: 0.42)
        }
    }

    // MARK: - Terrain decor (trees / flowers / rocks)

    private func drawTerrainDecor(
        context: GraphicsContext,
        x: Int,
        y: Int,
        biome: BiomeCatalog.BiomeInfo,
        canvas: CGSize
    ) {
        let tile = state.terrain.tile(x: x, y: y)
        let center = IsoMath.project(x: Double(x), y: Double(y),
                                     mapSize: state.repo.mapSize, canvas: canvas)
        let tw = IsoMath.tileWidth(forMapSize: state.repo.mapSize)
        switch tile {
        case .tree:
            drawTreeDecor(context: context, at: center, tw: tw, biome: biome)
        case .flower:
            drawFlowerDecor(context: context, at: center, tw: tw, biome: biome)
        case .rock:
            drawRockDecor(context: context, at: center, tw: tw)
        case .decor:
            drawLanternDecor(context: context, at: center, tw: tw)
        default:
            return
        }
    }

    private func drawTreeDecor(
        context: GraphicsContext,
        at center: CGPoint,
        tw: CGFloat,
        biome: BiomeCatalog.BiomeInfo
    ) {
        let trunk = CGRect(x: center.x - 1.5, y: center.y - 4, width: 3, height: 6)
        context.fill(Path(trunk), with: .color(Color(red: 0.36, green: 0.22, blue: 0.14)))
        let leafColor: Color = switch biome.biome {
        case .tundra: Color(red: 0.30, green: 0.50, blue: 0.36)
        case .desert: Color(red: 0.42, green: 0.62, blue: 0.36)
        case .beach:  Color(red: 0.45, green: 0.72, blue: 0.42)
        case .forest: Color(red: 0.20, green: 0.50, blue: 0.28)
        case .plain:  Color(red: 0.30, green: 0.62, blue: 0.32)
        }
        let crown = CGRect(x: center.x - tw / 3, y: center.y - tw / 2 - 4,
                           width: tw / 1.5, height: tw / 1.6)
        context.fill(Path(ellipseIn: crown), with: .color(leafColor))
        context.stroke(Path(ellipseIn: crown),
                       with: .color(leafColor.opacity(0.4)),
                       lineWidth: 0.5)
    }

    private func drawFlowerDecor(
        context: GraphicsContext,
        at center: CGPoint,
        tw: CGFloat,
        biome: BiomeCatalog.BiomeInfo
    ) {
        let color = biome.accentColor
        for offset in [CGPoint(x: -3, y: 0), CGPoint(x: 2, y: -2), CGPoint(x: 1, y: 3)] {
            let r: CGFloat = 1.6
            let rect = CGRect(x: center.x + offset.x - r,
                              y: center.y + offset.y - r,
                              width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
        _ = tw
    }

    private func drawRockDecor(
        context: GraphicsContext,
        at center: CGPoint,
        tw: CGFloat
    ) {
        let r = tw * 0.45
        let path = Path { p in
            p.move(to: CGPoint(x: center.x,         y: center.y - r * 0.5))
            p.addLine(to: CGPoint(x: center.x + r,  y: center.y))
            p.addLine(to: CGPoint(x: center.x,      y: center.y + r * 0.4))
            p.addLine(to: CGPoint(x: center.x - r,  y: center.y))
            p.closeSubpath()
        }
        context.fill(path, with: .color(Color(red: 0.62, green: 0.62, blue: 0.62)))
        context.stroke(path, with: .color(.black.opacity(0.3)), lineWidth: 0.5)
    }

    private func drawLanternDecor(
        context: GraphicsContext,
        at center: CGPoint,
        tw: CGFloat
    ) {
        let pole = CGRect(x: center.x - 1, y: center.y - 8, width: 2, height: 8)
        context.fill(Path(pole), with: .color(Color(red: 0.42, green: 0.30, blue: 0.20)))
        let lamp = CGRect(x: center.x - 3, y: center.y - 12, width: 6, height: 6)
        context.fill(Path(ellipseIn: lamp), with: .color(Color(red: 0.98, green: 0.88, blue: 0.55)))
        _ = tw
    }

    // MARK: - Buildings

    /// Project the back-most corner of a building's footprint to its
    /// on-screen base. The "back-most" is the (x, y) of the anchor tile
    /// because larger (x,y) draws further forward.
    private func drawBuilding(
        context: GraphicsContext,
        building: BuildingCatalog.Building,
        anchorX: Int,
        anchorY: Int,
        canvas: CGSize,
        alpha: Double
    ) {
        let shape = building.shape
        let mapSize = state.repo.mapSize
        let tw = IsoMath.tileWidth(forMapSize: mapSize)
        let th = IsoMath.tileHeight(forMapSize: mapSize)

        // The footprint's projected screen quad is the union of (anchor)
        // to (anchor + w-1, h-1). We approximate the building's "footprint
        // diamond" as the average of those four corners.
        let cTL = IsoMath.project(x: Double(anchorX), y: Double(anchorY),
                                  mapSize: mapSize, canvas: canvas)
        let cBR = IsoMath.project(x: Double(anchorX + shape.footprint.w - 1),
                                  y: Double(anchorY + shape.footprint.h - 1),
                                  mapSize: mapSize, canvas: canvas)
        let center = CGPoint(x: (cTL.x + cBR.x) / 2, y: (cTL.y + cBR.y) / 2)

        // The footprint diamond's half-axes.
        let halfW = tw * CGFloat(shape.footprint.w + shape.footprint.h - 1) * 0.5
        let halfH = th * CGFloat(shape.footprint.w + shape.footprint.h - 1) * 0.5

        // Stack stories from bottom to top, each shrinking by inset.
        var floorY = center.y
        var widthScale: CGFloat = 1.0
        var topCenter = CGPoint(x: center.x, y: center.y)

        let halfWBase = halfW * 0.82  // pull the building edges inside the tile diamond
        let halfHBase = halfH * 0.82

        for (i, story) in shape.stories.enumerated() {
            let insetScale = max(0.4, 1.0 - story.inset / max(1, halfWBase))
            widthScale = insetScale
            let halfWS = halfWBase * widthScale
            let halfHS = halfHBase * widthScale
            drawPrism(
                context: context,
                center: CGPoint(x: center.x, y: floorY),
                halfW: halfWS,
                halfH: halfHS,
                height: story.height,
                wallColor: story.wallColor.opacity(alpha),
                trimColor: story.trimColor?.opacity(alpha),
                isGround: i == 0,
                accent: shape.accent?.opacity(alpha)
            )
            floorY -= story.height
            topCenter = CGPoint(x: center.x, y: floorY)
        }

        // Roof
        let halfWTop = halfWBase * widthScale
        let halfHTop = halfHBase * widthScale
        drawRoof(
            context: context,
            roof: shape.roof,
            center: topCenter,
            halfW: halfWTop,
            halfH: halfHTop,
            alpha: alpha
        )

        // Ornament
        if let ornament = shape.ornament {
            drawOrnament(
                context: context,
                ornament: ornament,
                center: topCenter,
                halfW: halfWTop,
                halfH: halfHTop,
                alpha: alpha
            )
        }
    }

    private func drawPrism(
        context: GraphicsContext,
        center: CGPoint,
        halfW: CGFloat,
        halfH: CGFloat,
        height: CGFloat,
        wallColor: Color,
        trimColor: Color?,
        isGround: Bool,
        accent: Color?
    ) {
        let baseL = CGPoint(x: center.x - halfW, y: center.y)
        let baseR = CGPoint(x: center.x + halfW, y: center.y)
        let baseB = CGPoint(x: center.x,         y: center.y + halfH)
        let baseT = CGPoint(x: center.x,         y: center.y - halfH)

        let topL = CGPoint(x: baseL.x, y: baseL.y - height)
        let topR = CGPoint(x: baseR.x, y: baseR.y - height)
        let topB = CGPoint(x: baseB.x, y: baseB.y - height)
        let topT = CGPoint(x: baseT.x, y: baseT.y - height)

        // Left face (visible from camera POV)
        var leftFace = Path()
        leftFace.move(to: baseL)
        leftFace.addLine(to: baseB)
        leftFace.addLine(to: topB)
        leftFace.addLine(to: topL)
        leftFace.closeSubpath()
        context.fill(leftFace, with: .color(wallColor.opacity(0.92)))

        // Right face
        var rightFace = Path()
        rightFace.move(to: baseR)
        rightFace.addLine(to: baseB)
        rightFace.addLine(to: topB)
        rightFace.addLine(to: topR)
        rightFace.closeSubpath()
        context.fill(rightFace, with: .color(wallColor.opacity(0.74)))

        // Top diamond
        var top = Path()
        top.move(to: topT)
        top.addLine(to: topR)
        top.addLine(to: topB)
        top.addLine(to: topL)
        top.closeSubpath()
        context.fill(top, with: .color(wallColor))

        // Edges
        context.stroke(top, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
        context.stroke(leftFace, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
        context.stroke(rightFace, with: .color(.black.opacity(0.25)), lineWidth: 0.5)

        if let trim = trimColor, isGround {
            // Trim band at the base of the ground story.
            var band = Path()
            let bandHeight: CGFloat = max(2, height * 0.18)
            band.move(to: baseL)
            band.addLine(to: baseB)
            band.addLine(to: CGPoint(x: baseB.x, y: baseB.y - bandHeight))
            band.addLine(to: CGPoint(x: baseL.x, y: baseL.y - bandHeight))
            band.closeSubpath()
            context.fill(band, with: .color(trim.opacity(0.8)))
        }

        if let accent, isGround {
            // Door rectangle on the front-bottom face.
            let doorW = halfW * 0.18
            let doorH = height * 0.55
            let doorX = (baseL.x + baseB.x) / 2 - doorW / 2
            let doorY = baseB.y - doorH
            let doorRect = CGRect(x: doorX, y: doorY, width: doorW, height: doorH)
            context.fill(Path(doorRect), with: .color(accent))
        }
    }

    private func drawRoof(
        context: GraphicsContext,
        roof: BuildingShape.Roof,
        center: CGPoint,
        halfW: CGFloat,
        halfH: CGFloat,
        alpha: Double
    ) {
        switch roof {
        case .flat:
            return
        case let .gable(axis, height, color):
            drawGableRoof(context: context, center: center,
                          halfW: halfW, halfH: halfH,
                          height: height, color: color.opacity(alpha), axis: axis)
        case let .hip(height, color):
            drawHipRoof(context: context, center: center,
                        halfW: halfW, halfH: halfH,
                        height: height, color: color.opacity(alpha))
        case let .dome(height, color):
            drawDomeRoof(context: context, center: center,
                         halfW: halfW, halfH: halfH,
                         height: height, color: color.opacity(alpha))
        }
    }

    private func drawGableRoof(
        context: GraphicsContext,
        center: CGPoint,
        halfW: CGFloat,
        halfH: CGFloat,
        height: CGFloat,
        color: Color,
        axis: BuildingShape.Roof.Axis
    ) {
        let topT = CGPoint(x: center.x,         y: center.y - halfH)
        let topR = CGPoint(x: center.x + halfW, y: center.y)
        let topB = CGPoint(x: center.x,         y: center.y + halfH)
        let topL = CGPoint(x: center.x - halfW, y: center.y)
        // Ridge runs L-R when axis = x, B-T when axis = y.
        let ridge1: CGPoint
        let ridge2: CGPoint
        switch axis {
        case .x:
            ridge1 = CGPoint(x: topL.x, y: topL.y - height)
            ridge2 = CGPoint(x: topR.x, y: topR.y - height)
        case .y:
            ridge1 = CGPoint(x: topT.x, y: topT.y - height)
            ridge2 = CGPoint(x: topB.x, y: topB.y - height)
        }
        // Two slanted faces meeting at the ridge.
        var face1 = Path()
        face1.move(to: ridge1)
        face1.addLine(to: ridge2)
        face1.addLine(to: topR)
        face1.addLine(to: topT)
        face1.closeSubpath()
        var face2 = Path()
        face2.move(to: ridge1)
        face2.addLine(to: ridge2)
        face2.addLine(to: topB)
        face2.addLine(to: topL)
        face2.closeSubpath()
        context.fill(face2, with: .color(color.opacity(0.78)))
        context.fill(face1, with: .color(color))
        context.stroke(face1, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
        context.stroke(face2, with: .color(.black.opacity(0.30)), lineWidth: 0.5)
    }

    private func drawHipRoof(
        context: GraphicsContext,
        center: CGPoint,
        halfW: CGFloat,
        halfH: CGFloat,
        height: CGFloat,
        color: Color
    ) {
        let topT = CGPoint(x: center.x,         y: center.y - halfH)
        let topR = CGPoint(x: center.x + halfW, y: center.y)
        let topB = CGPoint(x: center.x,         y: center.y + halfH)
        let topL = CGPoint(x: center.x - halfW, y: center.y)
        let apex = CGPoint(x: center.x,         y: center.y - height)
        // Four triangles
        for (a, b, opacity) in [
            (topT, topR, 1.0),
            (topR, topB, 0.78),
            (topB, topL, 0.86),
            (topL, topT, 0.92),
        ] {
            var p = Path()
            p.move(to: apex)
            p.addLine(to: a)
            p.addLine(to: b)
            p.closeSubpath()
            context.fill(p, with: .color(color.opacity(opacity)))
            context.stroke(p, with: .color(.black.opacity(0.3)), lineWidth: 0.5)
        }
    }

    private func drawDomeRoof(
        context: GraphicsContext,
        center: CGPoint,
        halfW: CGFloat,
        halfH: CGFloat,
        height: CGFloat,
        color: Color
    ) {
        let rect = CGRect(
            x: center.x - halfW,
            y: center.y - height,
            width: halfW * 2,
            height: height * 2
        )
        var dome = Path()
        dome.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: halfW,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        // Close along the top diamond's east-west chord.
        dome.addLine(to: CGPoint(x: center.x + halfW, y: center.y))
        dome.addLine(to: CGPoint(x: center.x - halfW, y: center.y))
        dome.closeSubpath()
        context.fill(dome, with: .color(color))
        context.stroke(dome, with: .color(.black.opacity(0.30)), lineWidth: 0.6)
        _ = halfH
    }

    private func drawOrnament(
        context: GraphicsContext,
        ornament: BuildingShape.Ornament,
        center: CGPoint,
        halfW: CGFloat,
        halfH: CGFloat,
        alpha: Double
    ) {
        switch ornament {
        case let .chimney(side, height, color):
            let offset: CGPoint = switch side {
            case .n: CGPoint(x: 0,         y: -halfH * 0.5)
            case .e: CGPoint(x: halfW * 0.5, y: 0)
            case .s: CGPoint(x: 0,         y:  halfH * 0.5)
            case .w: CGPoint(x: -halfW * 0.5, y: 0)
            }
            let rect = CGRect(x: center.x + offset.x - 2.5,
                              y: center.y + offset.y - 4 - height,
                              width: 5, height: height)
            context.fill(Path(rect), with: .color(color.opacity(alpha)))
            context.stroke(Path(rect), with: .color(.black.opacity(0.3)), lineWidth: 0.5)
        case let .spire(height, color):
            var p = Path()
            p.move(to: CGPoint(x: center.x, y: center.y - height))
            p.addLine(to: CGPoint(x: center.x - 2, y: center.y))
            p.addLine(to: CGPoint(x: center.x + 2, y: center.y))
            p.closeSubpath()
            context.fill(p, with: .color(color.opacity(alpha)))
        case let .annex(side, depth, color):
            let offset: CGPoint = switch side {
            case .n: CGPoint(x: 0,           y: -halfH - depth / 2)
            case .e: CGPoint(x: halfW + depth / 2, y: 0)
            case .s: CGPoint(x: 0,           y:  halfH + depth / 2)
            case .w: CGPoint(x: -halfW - depth / 2, y: 0)
            }
            let rect = CGRect(x: center.x + offset.x - depth / 2,
                              y: center.y + offset.y - depth / 2,
                              width: depth, height: depth)
            context.fill(Path(rect), with: .color(color.opacity(alpha)))
        }
    }

    private func drawInvalidOverlay(
        context: GraphicsContext,
        building: BuildingCatalog.Building,
        anchorX: Int,
        anchorY: Int,
        canvas: CGSize
    ) {
        let mapSize = state.repo.mapSize
        let tw = IsoMath.tileWidth(forMapSize: mapSize)
        let th = IsoMath.tileHeight(forMapSize: mapSize)
        for dy in 0..<building.shape.footprint.h {
            for dx in 0..<building.shape.footprint.w {
                let center = IsoMath.project(x: Double(anchorX + dx),
                                             y: Double(anchorY + dy),
                                             mapSize: mapSize, canvas: canvas)
                var path = Path()
                path.move(to: CGPoint(x: center.x, y: center.y - th))
                path.addLine(to: CGPoint(x: center.x + tw, y: center.y))
                path.addLine(to: CGPoint(x: center.x, y: center.y + th))
                path.addLine(to: CGPoint(x: center.x - tw, y: center.y))
                path.closeSubpath()
                context.fill(path, with: .color(Color.red.opacity(0.28)))
            }
        }
    }

    // MARK: - Townsfolk

    private func drawTownsfolk(
        context: GraphicsContext,
        x: Double,
        y: Double,
        hue: Double,
        canvas: CGSize
    ) {
        let center = IsoMath.project(x: x, y: y,
                                     mapSize: state.repo.mapSize, canvas: canvas)
        let body = CGRect(x: center.x - 2.2, y: center.y - 7, width: 4.4, height: 6)
        let head = CGRect(x: center.x - 2, y: center.y - 11, width: 4, height: 4)
        let bodyColor = Color(hue: hue, saturation: 0.72, brightness: 0.86)
        let headColor = Color(hue: (hue + 0.05).truncatingRemainder(dividingBy: 1),
                              saturation: 0.42, brightness: 0.94)
        context.fill(Path(body), with: .color(bodyColor))
        context.fill(Path(ellipseIn: head), with: .color(headColor))
        context.stroke(Path(body), with: .color(.black.opacity(0.55)), lineWidth: 0.5)
        context.stroke(Path(ellipseIn: head), with: .color(.black.opacity(0.55)), lineWidth: 0.5)
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

import SwiftUI

/// Coordinate math for the isometric grid. Tile (x, y) on an `N×N` board
/// projects to screen using a classic 2:1 iso ratio. v3 — adds elevation
/// lift, a view transform (zoom + pan), and an inverse that accounts for
/// the view transform.
enum IsoMath {
    static let baseTileWidth: CGFloat = 28
    static let baseTileHeight: CGFloat = 14
    /// Vertical lift per elevation tier (in screen px, pre-zoom).
    static let elevationStep: CGFloat = 8

    /// View transform — discrete zoom level + pan offset in screen px.
    struct ViewTransform: Equatable {
        var zoom: Double = 1.0
        var panX: CGFloat = 0
        var panY: CGFloat = 0
        static let identity = ViewTransform()
        static let allZooms: [Double] = [0.75, 1.0, 1.5]
    }

    static func tileWidth(forMapSize size: Int, zoom: Double = 1.0) -> CGFloat {
        let base: CGFloat = switch size {
        case ..<14: baseTileWidth + 6
        case 14..<20: baseTileWidth + 2
        case 20..<32: baseTileWidth
        default: baseTileWidth - 4
        }
        return base * CGFloat(zoom)
    }

    static func tileHeight(forMapSize size: Int, zoom: Double = 1.0) -> CGFloat {
        tileWidth(forMapSize: size, zoom: zoom) / 2
    }

    static func elevationOffset(_ elevation: Int, zoom: Double = 1.0) -> CGFloat {
        elevationStep * CGFloat(elevation) * CGFloat(zoom)
    }

    static func project(
        x: Double,
        y: Double,
        elevation: Int = 0,
        mapSize: Int,
        canvas: CGSize,
        view: ViewTransform = .identity
    ) -> CGPoint {
        let tw = tileWidth(forMapSize: mapSize, zoom: view.zoom)
        let th = tileHeight(forMapSize: mapSize, zoom: view.zoom)
        let originX = canvas.width / 2 + view.panX
        let originY = canvas.height / 2 - CGFloat(mapSize) * th / 2 + view.panY
        let sx = (x - y) * tw + originX
        let sy = (x + y) * th + originY - elevationOffset(elevation, zoom: view.zoom)
        return CGPoint(x: sx, y: sy)
    }

    static func unproject(
        _ p: CGPoint,
        mapSize: Int,
        canvas: CGSize,
        view: ViewTransform = .identity
    ) -> (x: Int, y: Int)? {
        let tw = tileWidth(forMapSize: mapSize, zoom: view.zoom)
        let th = tileHeight(forMapSize: mapSize, zoom: view.zoom)
        let originX = canvas.width / 2 + view.panX
        let originY = canvas.height / 2 - CGFloat(mapSize) * th / 2 + view.panY
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

/// Procedural isometric tile renderer. v3 adds:
///   - elevation lift + side cliffs
///   - per-tile sub-detail (grass tufts, sand ripples, snow flecks) seeded by townId
///   - autotiled roads (narrow + sidewalks + neighbor-aware variants)
///   - building badges (small marker beside each building)
///   - view transform (zoom + pan)
///   - cardinal-only townsfolk interpolation (current→nextStep, never to ultimate goal)
struct IsoTileRenderer: View {
    let state: TokeyoTownState
    let phase: Double
    let placementPreview: PlacementPreview?
    let view: IsoMath.ViewTransform

    struct PlacementPreview {
        let kind: String
        let tile: (x: Int, y: Int)
        let valid: Bool
    }

    var body: some View {
        Canvas { context, size in
            let biome = BiomeCatalog.info(state.repo.biome)
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(skyColor(for: biome)))

            // Ground (with elevation lift + side cliffs)
            for y in 0..<state.repo.mapSize {
                for x in 0..<state.repo.mapSize {
                    drawGroundTile(context: context, x: x, y: y, biome: biome, canvas: size)
                }
            }

            // Tile sub-details (grass tufts, sand ripples, etc.)
            for y in 0..<state.repo.mapSize {
                for x in 0..<state.repo.mapSize {
                    drawTileSubDetail(context: context, x: x, y: y, biome: biome, canvas: size)
                }
            }

            // Terrain decor (trees, flowers, rocks, lanterns)
            for y in 0..<state.repo.mapSize {
                for x in 0..<state.repo.mapSize {
                    drawTerrainDecor(context: context, x: x, y: y, biome: biome, canvas: size)
                }
            }

            // Roads (drawn after terrain so sidewalks sit on top of the ground tile)
            for y in 0..<state.repo.mapSize {
                for x in 0..<state.repo.mapSize {
                    if state.terrain.tile(x: x, y: y) == .road {
                        drawRoadTile(context: context, x: x, y: y, biome: biome, canvas: size)
                    }
                }
            }

            // Buildings — back-to-front by tile sum
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
                if !preview.valid {
                    drawInvalidOverlay(context: context, building: b,
                                       anchorX: preview.tile.x, anchorY: preview.tile.y,
                                       canvas: size)
                }
            }

            // Townsfolk (cardinal interpolation: current → nextStep only)
            for npc in state.townsfolk {
                let next = npc.nextStep ?? (Int(npc.tileX.rounded()), Int(npc.tileY.rounded()))
                let dx = Double(next.0) - npc.tileX
                let dy = Double(next.1) - npc.tileY
                let interpX = npc.tileX + dx * phase
                let interpY = npc.tileY + dy * phase
                let elev = state.terrain.elev(
                    x: Int(interpX.rounded()),
                    y: Int(interpY.rounded())
                )
                drawTownsfolk(context: context,
                              x: interpX, y: interpY, elevation: elev,
                              hue: npc.hue, canvas: size)
            }
        }
    }

    // MARK: - Ground + cliffs

    private func drawGroundTile(
        context: GraphicsContext,
        x: Int,
        y: Int,
        biome: BiomeCatalog.BiomeInfo,
        canvas: CGSize
    ) {
        let tile = state.terrain.tile(x: x, y: y)
        let elev = state.terrain.elev(x: x, y: y)
        let center = IsoMath.project(x: Double(x), y: Double(y),
                                     elevation: elev,
                                     mapSize: state.repo.mapSize,
                                     canvas: canvas, view: view)
        let tw = IsoMath.tileWidth(forMapSize: state.repo.mapSize, zoom: view.zoom)
        let th = IsoMath.tileHeight(forMapSize: state.repo.mapSize, zoom: view.zoom)

        // Side faces between this tile and its south + east neighbors
        // when this tile is higher — gives cliff faces on hills.
        let southElev = state.terrain.elev(x: x, y: y + 1)
        let eastElev = state.terrain.elev(x: x + 1, y: y)

        // South-facing wall
        if elev > southElev {
            let drop = IsoMath.elevationOffset(elev - southElev, zoom: view.zoom)
            var wall = Path()
            wall.move(to: CGPoint(x: center.x - tw, y: center.y))
            wall.addLine(to: CGPoint(x: center.x, y: center.y + th))
            wall.addLine(to: CGPoint(x: center.x, y: center.y + th + drop))
            wall.addLine(to: CGPoint(x: center.x - tw, y: center.y + drop))
            wall.closeSubpath()
            context.fill(wall, with: .color(cliffColor(for: biome).opacity(0.85)))
        }
        // East-facing wall
        if elev > eastElev {
            let drop = IsoMath.elevationOffset(elev - eastElev, zoom: view.zoom)
            var wall = Path()
            wall.move(to: CGPoint(x: center.x + tw, y: center.y))
            wall.addLine(to: CGPoint(x: center.x, y: center.y + th))
            wall.addLine(to: CGPoint(x: center.x, y: center.y + th + drop))
            wall.addLine(to: CGPoint(x: center.x + tw, y: center.y + drop))
            wall.closeSubpath()
            context.fill(wall, with: .color(cliffColor(for: biome).opacity(0.72)))
        }

        // The tile diamond itself
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - th))
        path.addLine(to: CGPoint(x: center.x + tw, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + th))
        path.addLine(to: CGPoint(x: center.x - tw, y: center.y))
        path.closeSubpath()

        context.fill(path, with: .color(groundColor(for: tile, biome: biome)))
        context.stroke(path,
                       with: .color(biome.groundShadeColor.opacity(0.35)),
                       lineWidth: 0.5)
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
            return biome.groundColor.opacity(lush * 0.5 + 0.5)
        case .rock:
            return Color(red: 0.62, green: 0.60, blue: 0.55)
        case .tree, .flower, .decor:
            return biome.groundColor.opacity(lush * 0.5 + 0.5)
        case .road:
            // Roads sit on the underlying grass/sand color so the sidewalks
            // sticker correctly on top. The road strip itself draws later.
            return biome.groundColor.opacity(lush * 0.5 + 0.5)
        }
    }

    private func cliffColor(for biome: BiomeCatalog.BiomeInfo) -> Color {
        switch biome.biome {
        case .tundra: return Color(red: 0.55, green: 0.55, blue: 0.60)
        case .desert: return Color(red: 0.62, green: 0.45, blue: 0.30)
        case .forest: return Color(red: 0.42, green: 0.32, blue: 0.22)
        case .beach:  return Color(red: 0.72, green: 0.58, blue: 0.42)
        case .plain:  return Color(red: 0.50, green: 0.42, blue: 0.30)
        }
    }

    // MARK: - Per-tile sub-detail

    /// Tiny dots/strokes seeded by townId + tile coords so the texture is
    /// stable per town and varies tile-to-tile. Kept extremely cheap.
    private func drawTileSubDetail(
        context: GraphicsContext,
        x: Int,
        y: Int,
        biome: BiomeCatalog.BiomeInfo,
        canvas: CGSize
    ) {
        let tile = state.terrain.tile(x: x, y: y)
        guard tile == .grass || tile == .sand else { return }
        let elev = state.terrain.elev(x: x, y: y)
        let center = IsoMath.project(x: Double(x), y: Double(y),
                                     elevation: elev,
                                     mapSize: state.repo.mapSize,
                                     canvas: canvas, view: view)
        let tw = IsoMath.tileWidth(forMapSize: state.repo.mapSize, zoom: view.zoom)
        var rng = TileRNG(seed: tileSeed(x: x, y: y))

        let count = tile == .grass ? 3 : 2
        for _ in 0..<count {
            let dx = (rng.next() * 2 - 1) * tw * 0.55
            let dy = (rng.next() * 2 - 1) * tw * 0.28
            let p = CGPoint(x: center.x + dx, y: center.y + dy)
            switch tile {
            case .grass:
                // Three tiny grass strokes
                var stroke = Path()
                stroke.move(to: p)
                stroke.addLine(to: CGPoint(x: p.x + (rng.next() - 0.5) * 2,
                                           y: p.y - 1.5 - rng.next()))
                context.stroke(stroke,
                               with: .color(Color(red: 0.22, green: 0.45, blue: 0.22).opacity(0.5)),
                               lineWidth: 0.6)
            case .sand:
                // Tiny ripple — short horizontal arc
                var arc = Path()
                arc.move(to: CGPoint(x: p.x - 2, y: p.y))
                arc.addQuadCurve(
                    to: CGPoint(x: p.x + 2, y: p.y),
                    control: CGPoint(x: p.x, y: p.y - 1.4)
                )
                context.stroke(arc,
                               with: .color(biome.groundShadeColor.opacity(0.45)),
                               lineWidth: 0.5)
            default: break
            }
        }
    }

    private func tileSeed(x: Int, y: Int) -> UInt64 {
        let base = TerrainGenerator.seed(for: state.townId)
        return base &+ UInt64(x) &* 73_856_093 &+ UInt64(y) &* 19_349_663
    }

    // MARK: - Terrain decor

    private func drawTerrainDecor(
        context: GraphicsContext,
        x: Int,
        y: Int,
        biome: BiomeCatalog.BiomeInfo,
        canvas: CGSize
    ) {
        let tile = state.terrain.tile(x: x, y: y)
        let elev = state.terrain.elev(x: x, y: y)
        let center = IsoMath.project(x: Double(x), y: Double(y),
                                     elevation: elev,
                                     mapSize: state.repo.mapSize,
                                     canvas: canvas, view: view)
        let tw = IsoMath.tileWidth(forMapSize: state.repo.mapSize, zoom: view.zoom)
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

    private func drawTreeDecor(context: GraphicsContext, at center: CGPoint,
                               tw: CGFloat, biome: BiomeCatalog.BiomeInfo) {
        let trunkH = tw * 0.18
        let trunk = CGRect(x: center.x - 1.6, y: center.y - trunkH,
                           width: 3.2, height: trunkH)
        context.fill(Path(trunk), with: .color(Color(red: 0.36, green: 0.22, blue: 0.14)))
        let leafColor: Color = switch biome.biome {
        case .tundra: Color(red: 0.30, green: 0.50, blue: 0.36)
        case .desert: Color(red: 0.42, green: 0.62, blue: 0.36)
        case .beach:  Color(red: 0.45, green: 0.72, blue: 0.42)
        case .forest: Color(red: 0.20, green: 0.50, blue: 0.28)
        case .plain:  Color(red: 0.30, green: 0.62, blue: 0.32)
        }
        let crown = CGRect(x: center.x - tw / 2.8,
                           y: center.y - tw / 1.6,
                           width: tw / 1.4, height: tw / 1.4)
        context.fill(Path(ellipseIn: crown), with: .color(leafColor))
        context.stroke(Path(ellipseIn: crown),
                       with: .color(leafColor.opacity(0.4)), lineWidth: 0.5)
    }

    private func drawFlowerDecor(context: GraphicsContext, at center: CGPoint,
                                 tw: CGFloat, biome: BiomeCatalog.BiomeInfo) {
        let color = biome.accentColor
        for offset in [CGPoint(x: -3, y: 0), CGPoint(x: 2, y: -2), CGPoint(x: 1, y: 3)] {
            let r: CGFloat = 1.7
            let rect = CGRect(x: center.x + offset.x - r,
                              y: center.y + offset.y - r,
                              width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
        _ = tw
    }

    private func drawRockDecor(context: GraphicsContext, at center: CGPoint, tw: CGFloat) {
        // Rocks look like little jagged ridges; for tier-2 mountains, draw
        // a darker peaked silhouette on top.
        let r = tw * 0.42
        let path = Path { p in
            p.move(to: CGPoint(x: center.x, y: center.y - r * 0.6))
            p.addLine(to: CGPoint(x: center.x + r, y: center.y))
            p.addLine(to: CGPoint(x: center.x, y: center.y + r * 0.35))
            p.addLine(to: CGPoint(x: center.x - r, y: center.y))
            p.closeSubpath()
        }
        context.fill(path, with: .color(Color(red: 0.60, green: 0.58, blue: 0.55)))
        context.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
        // Peak hint
        var peak = Path()
        peak.move(to: CGPoint(x: center.x - r * 0.5, y: center.y - r * 0.3))
        peak.addLine(to: CGPoint(x: center.x, y: center.y - r * 0.95))
        peak.addLine(to: CGPoint(x: center.x + r * 0.5, y: center.y - r * 0.3))
        peak.closeSubpath()
        context.fill(peak, with: .color(.black.opacity(0.18)))
    }

    private func drawLanternDecor(context: GraphicsContext, at center: CGPoint, tw: CGFloat) {
        let pole = CGRect(x: center.x - 1, y: center.y - 9, width: 2, height: 9)
        context.fill(Path(pole), with: .color(Color(red: 0.42, green: 0.30, blue: 0.20)))
        let lamp = CGRect(x: center.x - 3.2, y: center.y - 13,
                          width: 6.4, height: 6.4)
        context.fill(Path(ellipseIn: lamp),
                     with: .color(Color(red: 0.98, green: 0.88, blue: 0.55)))
        context.stroke(Path(ellipseIn: lamp),
                       with: .color(.black.opacity(0.35)), lineWidth: 0.5)
        _ = tw
    }

    // MARK: - Roads (autotiled with sidewalks)

    /// 4-bit neighbor mask — N=1, E=2, S=4, W=8 — bitwise OR of any neighbor
    /// that should "connect" (road tile or a building face).
    private func roadConnectivityMask(x: Int, y: Int) -> Int {
        var mask = 0
        if connectsRoadAt(x: x, y: y - 1) { mask |= 1 }
        if connectsRoadAt(x: x + 1, y: y) { mask |= 2 }
        if connectsRoadAt(x: x, y: y + 1) { mask |= 4 }
        if connectsRoadAt(x: x - 1, y: y) { mask |= 8 }
        return mask
    }

    private func connectsRoadAt(x: Int, y: Int) -> Bool {
        guard state.terrain.contains(x: x, y: y) else { return false }
        if state.terrain.tile(x: x, y: y) == .road { return true }
        // Building edge — extend road into adjacent buildings
        for b in state.buildings where
            x >= b.tileX && x < b.tileX + b.width &&
            y >= b.tileY && y < b.tileY + b.height {
            return true
        }
        return false
    }

    private func drawRoadTile(
        context: GraphicsContext,
        x: Int,
        y: Int,
        biome: BiomeCatalog.BiomeInfo,
        canvas: CGSize
    ) {
        let elev = state.terrain.elev(x: x, y: y)
        let center = IsoMath.project(x: Double(x), y: Double(y),
                                     elevation: elev,
                                     mapSize: state.repo.mapSize,
                                     canvas: canvas, view: view)
        let tw = IsoMath.tileWidth(forMapSize: state.repo.mapSize, zoom: view.zoom)
        let th = IsoMath.tileHeight(forMapSize: state.repo.mapSize, zoom: view.zoom)
        let mask = roadConnectivityMask(x: x, y: y)
        let sidewalk = sidewalkColor(for: biome)
        let asphalt = asphaltColor(for: biome)

        // Two strips, NS and EW. Each strip is a thin diamond
        // (a fraction of the tile's full diamond). Together they form
        // crosses / Ts / straights / curves / ends naturally.
        let stripWidth: CGFloat = tw * 0.42       // half-width of road strip
        let stripHeight: CGFloat = th * 0.42

        let connectsN = (mask & 1) != 0
        let connectsE = (mask & 2) != 0
        let connectsS = (mask & 4) != 0
        let connectsW = (mask & 8) != 0

        // Endpoints for each strip — extend out to the tile edge in
        // directions that connect, otherwise stop short at the road center.
        let nStop = connectsN ? -th : -th * 0.35
        let sStop = connectsS ?  th :  th * 0.35
        let eStop = connectsE ?  tw :  tw * 0.35
        let wStop = connectsW ? -tw : -tw * 0.35

        // NS strip (diamond from N to S, narrow E-W)
        if connectsN || connectsS || (!connectsE && !connectsW) {
            var stripBack = Path()
            stripBack.move(to: CGPoint(x: center.x - stripWidth - 1, y: center.y))
            stripBack.addLine(to: CGPoint(x: center.x, y: center.y + nStop - 1))
            stripBack.addLine(to: CGPoint(x: center.x + stripWidth + 1, y: center.y))
            stripBack.addLine(to: CGPoint(x: center.x, y: center.y + sStop + 1))
            stripBack.closeSubpath()
            context.fill(stripBack, with: .color(sidewalk))

            var strip = Path()
            strip.move(to: CGPoint(x: center.x - stripWidth + 2, y: center.y))
            strip.addLine(to: CGPoint(x: center.x, y: center.y + nStop + 1))
            strip.addLine(to: CGPoint(x: center.x + stripWidth - 2, y: center.y))
            strip.addLine(to: CGPoint(x: center.x, y: center.y + sStop - 1))
            strip.closeSubpath()
            context.fill(strip, with: .color(asphalt))
        }

        // EW strip
        if connectsE || connectsW || (!connectsN && !connectsS) {
            var stripBack = Path()
            stripBack.move(to: CGPoint(x: center.x, y: center.y - stripHeight - 1))
            stripBack.addLine(to: CGPoint(x: center.x + eStop + 1, y: center.y))
            stripBack.addLine(to: CGPoint(x: center.x, y: center.y + stripHeight + 1))
            stripBack.addLine(to: CGPoint(x: center.x + wStop - 1, y: center.y))
            stripBack.closeSubpath()
            context.fill(stripBack, with: .color(sidewalk))

            var strip = Path()
            strip.move(to: CGPoint(x: center.x, y: center.y - stripHeight + 1))
            strip.addLine(to: CGPoint(x: center.x + eStop - 1, y: center.y))
            strip.addLine(to: CGPoint(x: center.x, y: center.y + stripHeight - 1))
            strip.addLine(to: CGPoint(x: center.x + wStop + 1, y: center.y))
            strip.closeSubpath()
            context.fill(strip, with: .color(asphalt))
        }

        // Center dashes if this tile is a straight (cross-stripe omitted).
        let isStraight = (connectsN && connectsS && !connectsE && !connectsW) ||
            (connectsE && connectsW && !connectsN && !connectsS)
        if isStraight {
            let dash = CGRect(x: center.x - 1, y: center.y - 1.4, width: 2, height: 2.8)
            context.fill(Path(dash), with: .color(.white.opacity(0.6)))
        }
    }

    private func asphaltColor(for biome: BiomeCatalog.BiomeInfo) -> Color {
        switch biome.biome {
        case .plain:  return Color(red: 0.32, green: 0.32, blue: 0.34)
        case .desert: return Color(red: 0.45, green: 0.36, blue: 0.30)
        case .tundra: return Color(red: 0.30, green: 0.32, blue: 0.36)
        case .forest: return Color(red: 0.28, green: 0.28, blue: 0.28)
        case .beach:  return Color(red: 0.52, green: 0.42, blue: 0.32)  // boardwalk planks
        }
    }

    private func sidewalkColor(for biome: BiomeCatalog.BiomeInfo) -> Color {
        switch biome.biome {
        case .beach:  return Color(red: 0.88, green: 0.78, blue: 0.55)
        default:      return Color(red: 0.78, green: 0.78, blue: 0.74)
        }
    }

    // MARK: - Buildings

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
        let zoom = view.zoom
        let tw = IsoMath.tileWidth(forMapSize: mapSize, zoom: zoom)
        let th = IsoMath.tileHeight(forMapSize: mapSize, zoom: zoom)
        let anchorElev = state.terrain.elev(x: anchorX, y: anchorY)
        let cTL = IsoMath.project(x: Double(anchorX), y: Double(anchorY),
                                  elevation: anchorElev,
                                  mapSize: mapSize, canvas: canvas, view: view)
        let cBR = IsoMath.project(
            x: Double(anchorX + shape.footprint.w - 1),
            y: Double(anchorY + shape.footprint.h - 1),
            elevation: anchorElev,
            mapSize: mapSize, canvas: canvas, view: view
        )
        let center = CGPoint(x: (cTL.x + cBR.x) / 2, y: (cTL.y + cBR.y) / 2)
        let halfWBase = tw * CGFloat(shape.footprint.w + shape.footprint.h - 1) * 0.5 * 0.82
        let halfHBase = th * CGFloat(shape.footprint.w + shape.footprint.h - 1) * 0.5 * 0.82

        var floorY = center.y
        var widthScale: CGFloat = 1.0
        var topCenter = center

        for (i, story) in shape.stories.enumerated() {
            let insetScale = max(0.4, 1.0 - story.inset / max(1, halfWBase))
            widthScale = insetScale
            let halfWS = halfWBase * widthScale
            let halfHS = halfHBase * widthScale
            let scaledStoryHeight = story.height * CGFloat(zoom)
            drawPrism(
                context: context,
                center: CGPoint(x: center.x, y: floorY),
                halfW: halfWS,
                halfH: halfHS,
                height: scaledStoryHeight,
                wallColor: story.wallColor.opacity(alpha),
                trimColor: story.trimColor?.opacity(alpha),
                isGround: i == 0,
                accent: shape.accent?.opacity(alpha)
            )
            floorY -= scaledStoryHeight
            topCenter = CGPoint(x: center.x, y: floorY)
        }

        let halfWTop = halfWBase * widthScale
        let halfHTop = halfHBase * widthScale
        drawRoof(context: context, roof: shape.roof,
                 center: topCenter,
                 halfW: halfWTop, halfH: halfHTop,
                 zoom: zoom, alpha: alpha)

        if let ornament = shape.ornament {
            drawOrnament(context: context, ornament: ornament,
                         center: topCenter,
                         halfW: halfWTop, halfH: halfHTop,
                         zoom: zoom, alpha: alpha)
        }

        // Badge — a colored circle with the glyph below the right corner.
        if alpha >= 0.99 {
            drawBuildingBadge(context: context, glyph: building.glyph,
                              color: badgeColor(for: building),
                              at: CGPoint(x: center.x + halfWBase * 0.55,
                                          y: center.y + halfHBase * 0.6))
        }
    }

    private func badgeColor(for b: BuildingCatalog.Building) -> Color {
        // Subtle tint per biome + a stronger fixed accent for visibility.
        switch b.biome {
        case .plain:  return Color(red: 0.95, green: 0.85, blue: 0.30)
        case .desert: return Color(red: 0.95, green: 0.62, blue: 0.30)
        case .tundra: return Color(red: 0.62, green: 0.78, blue: 0.92)
        case .forest: return Color(red: 0.55, green: 0.78, blue: 0.42)
        case .beach:  return Color(red: 0.92, green: 0.42, blue: 0.62)
        }
    }

    private func drawBuildingBadge(context: GraphicsContext, glyph: String,
                                   color: Color, at point: CGPoint) {
        let r: CGFloat = 7 * CGFloat(view.zoom)
        let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.92)))
        context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1.5)
        let glyphResolved = context.resolve(
            Text(glyph).font(.system(size: 9 * CGFloat(view.zoom)))
        )
        context.draw(glyphResolved, at: point, anchor: .center)
    }

    private func drawPrism(
        context: GraphicsContext, center: CGPoint,
        halfW: CGFloat, halfH: CGFloat, height: CGFloat,
        wallColor: Color, trimColor: Color?,
        isGround: Bool, accent: Color?
    ) {
        let baseL = CGPoint(x: center.x - halfW, y: center.y)
        let baseR = CGPoint(x: center.x + halfW, y: center.y)
        let baseB = CGPoint(x: center.x, y: center.y + halfH)
        let baseT = CGPoint(x: center.x, y: center.y - halfH)
        let topL = CGPoint(x: baseL.x, y: baseL.y - height)
        let topR = CGPoint(x: baseR.x, y: baseR.y - height)
        let topB = CGPoint(x: baseB.x, y: baseB.y - height)
        let topT = CGPoint(x: baseT.x, y: baseT.y - height)

        var leftFace = Path()
        leftFace.move(to: baseL); leftFace.addLine(to: baseB)
        leftFace.addLine(to: topB); leftFace.addLine(to: topL); leftFace.closeSubpath()
        context.fill(leftFace, with: .color(wallColor.opacity(0.92)))

        var rightFace = Path()
        rightFace.move(to: baseR); rightFace.addLine(to: baseB)
        rightFace.addLine(to: topB); rightFace.addLine(to: topR); rightFace.closeSubpath()
        context.fill(rightFace, with: .color(wallColor.opacity(0.74)))

        var top = Path()
        top.move(to: topT); top.addLine(to: topR); top.addLine(to: topB); top.addLine(to: topL)
        top.closeSubpath()
        context.fill(top, with: .color(wallColor))

        context.stroke(top, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
        context.stroke(leftFace, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
        context.stroke(rightFace, with: .color(.black.opacity(0.25)), lineWidth: 0.5)

        if let trim = trimColor, isGround {
            var band = Path()
            let bandHeight: CGFloat = max(2, height * 0.18)
            band.move(to: baseL); band.addLine(to: baseB)
            band.addLine(to: CGPoint(x: baseB.x, y: baseB.y - bandHeight))
            band.addLine(to: CGPoint(x: baseL.x, y: baseL.y - bandHeight))
            band.closeSubpath()
            context.fill(band, with: .color(trim.opacity(0.8)))
        }
        if let accent, isGround {
            let doorW = halfW * 0.18
            let doorH = height * 0.55
            let doorX = (baseL.x + baseB.x) / 2 - doorW / 2
            let doorY = baseB.y - doorH
            context.fill(Path(CGRect(x: doorX, y: doorY, width: doorW, height: doorH)),
                         with: .color(accent))
        }
    }

    private func drawRoof(
        context: GraphicsContext, roof: BuildingShape.Roof,
        center: CGPoint, halfW: CGFloat, halfH: CGFloat,
        zoom: Double, alpha: Double
    ) {
        switch roof {
        case .flat: return
        case let .gable(axis, height, color):
            drawGable(context: context, center: center, halfW: halfW, halfH: halfH,
                      height: height * CGFloat(zoom), color: color.opacity(alpha), axis: axis)
        case let .hip(height, color):
            drawHip(context: context, center: center, halfW: halfW, halfH: halfH,
                    height: height * CGFloat(zoom), color: color.opacity(alpha))
        case let .dome(height, color):
            drawDome(context: context, center: center, halfW: halfW, halfH: halfH,
                     height: height * CGFloat(zoom), color: color.opacity(alpha))
        }
    }

    private func drawGable(context: GraphicsContext, center: CGPoint,
                           halfW: CGFloat, halfH: CGFloat,
                           height: CGFloat, color: Color,
                           axis: BuildingShape.Roof.Axis) {
        let topT = CGPoint(x: center.x, y: center.y - halfH)
        let topR = CGPoint(x: center.x + halfW, y: center.y)
        let topB = CGPoint(x: center.x, y: center.y + halfH)
        let topL = CGPoint(x: center.x - halfW, y: center.y)
        let r1: CGPoint
        let r2: CGPoint
        switch axis {
        case .x:
            r1 = CGPoint(x: topL.x, y: topL.y - height)
            r2 = CGPoint(x: topR.x, y: topR.y - height)
        case .y:
            r1 = CGPoint(x: topT.x, y: topT.y - height)
            r2 = CGPoint(x: topB.x, y: topB.y - height)
        }
        var face1 = Path()
        face1.move(to: r1); face1.addLine(to: r2); face1.addLine(to: topR); face1.addLine(to: topT)
        face1.closeSubpath()
        var face2 = Path()
        face2.move(to: r1); face2.addLine(to: r2); face2.addLine(to: topB); face2.addLine(to: topL)
        face2.closeSubpath()
        context.fill(face2, with: .color(color.opacity(0.78)))
        context.fill(face1, with: .color(color))
        context.stroke(face1, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
        context.stroke(face2, with: .color(.black.opacity(0.30)), lineWidth: 0.5)
    }

    private func drawHip(context: GraphicsContext, center: CGPoint,
                         halfW: CGFloat, halfH: CGFloat,
                         height: CGFloat, color: Color) {
        let topT = CGPoint(x: center.x, y: center.y - halfH)
        let topR = CGPoint(x: center.x + halfW, y: center.y)
        let topB = CGPoint(x: center.x, y: center.y + halfH)
        let topL = CGPoint(x: center.x - halfW, y: center.y)
        let apex = CGPoint(x: center.x, y: center.y - height)
        for (a, b, opacity) in [
            (topT, topR, 1.0), (topR, topB, 0.78), (topB, topL, 0.86), (topL, topT, 0.92),
        ] {
            var p = Path()
            p.move(to: apex); p.addLine(to: a); p.addLine(to: b); p.closeSubpath()
            context.fill(p, with: .color(color.opacity(opacity)))
            context.stroke(p, with: .color(.black.opacity(0.3)), lineWidth: 0.5)
        }
    }

    private func drawDome(context: GraphicsContext, center: CGPoint,
                          halfW: CGFloat, halfH: CGFloat,
                          height: CGFloat, color: Color) {
        var dome = Path()
        dome.addArc(
            center: CGPoint(x: center.x, y: center.y),
            radius: halfW,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        dome.addLine(to: CGPoint(x: center.x + halfW, y: center.y))
        dome.addLine(to: CGPoint(x: center.x - halfW, y: center.y))
        dome.closeSubpath()
        context.fill(dome, with: .color(color))
        context.stroke(dome, with: .color(.black.opacity(0.30)), lineWidth: 0.6)
        _ = halfH; _ = height
    }

    private func drawOrnament(context: GraphicsContext,
                              ornament: BuildingShape.Ornament,
                              center: CGPoint, halfW: CGFloat, halfH: CGFloat,
                              zoom: Double, alpha: Double) {
        switch ornament {
        case let .chimney(side, height, color):
            let offset: CGPoint = switch side {
            case .n: CGPoint(x: 0, y: -halfH * 0.5)
            case .e: CGPoint(x: halfW * 0.5, y: 0)
            case .s: CGPoint(x: 0, y: halfH * 0.5)
            case .w: CGPoint(x: -halfW * 0.5, y: 0)
            }
            let h = height * CGFloat(zoom)
            let rect = CGRect(x: center.x + offset.x - 2.5,
                              y: center.y + offset.y - 4 - h,
                              width: 5, height: h)
            context.fill(Path(rect), with: .color(color.opacity(alpha)))
            context.stroke(Path(rect), with: .color(.black.opacity(0.3)), lineWidth: 0.5)
        case let .spire(height, color):
            let h = height * CGFloat(zoom)
            var p = Path()
            p.move(to: CGPoint(x: center.x, y: center.y - h))
            p.addLine(to: CGPoint(x: center.x - 2, y: center.y))
            p.addLine(to: CGPoint(x: center.x + 2, y: center.y))
            p.closeSubpath()
            context.fill(p, with: .color(color.opacity(alpha)))
        case let .annex(side, depth, color):
            let d = depth * CGFloat(zoom)
            let offset: CGPoint = switch side {
            case .n: CGPoint(x: 0, y: -halfH - d / 2)
            case .e: CGPoint(x: halfW + d / 2, y: 0)
            case .s: CGPoint(x: 0, y: halfH + d / 2)
            case .w: CGPoint(x: -halfW - d / 2, y: 0)
            }
            let rect = CGRect(x: center.x + offset.x - d / 2,
                              y: center.y + offset.y - d / 2,
                              width: d, height: d)
            context.fill(Path(rect), with: .color(color.opacity(alpha)))
        }
    }

    private func drawInvalidOverlay(
        context: GraphicsContext, building: BuildingCatalog.Building,
        anchorX: Int, anchorY: Int, canvas: CGSize
    ) {
        let mapSize = state.repo.mapSize
        let tw = IsoMath.tileWidth(forMapSize: mapSize, zoom: view.zoom)
        let th = IsoMath.tileHeight(forMapSize: mapSize, zoom: view.zoom)
        for dy in 0..<building.shape.footprint.h {
            for dx in 0..<building.shape.footprint.w {
                let elev = state.terrain.elev(x: anchorX + dx, y: anchorY + dy)
                let center = IsoMath.project(
                    x: Double(anchorX + dx), y: Double(anchorY + dy),
                    elevation: elev,
                    mapSize: mapSize, canvas: canvas, view: view
                )
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
        x: Double, y: Double, elevation: Int,
        hue: Double, canvas: CGSize
    ) {
        let center = IsoMath.project(x: x, y: y,
                                     elevation: elevation,
                                     mapSize: state.repo.mapSize,
                                     canvas: canvas, view: view)
        let zoom = CGFloat(view.zoom)
        let body = CGRect(x: center.x - 2.4 * zoom, y: center.y - 7 * zoom,
                          width: 4.8 * zoom, height: 6 * zoom)
        let head = CGRect(x: center.x - 2.2 * zoom, y: center.y - 12 * zoom,
                          width: 4.4 * zoom, height: 4.4 * zoom)
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

/// Tiny PRNG used by tile sub-detail. Deterministic per (townId, x, y).
private struct TileRNG {
    private var state: UInt64
    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

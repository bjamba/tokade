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
        // Round-to-nearest. Tile (x, y) has its center at (fx, fy) =
        // (x, y); the iso diamond boundary between adjacent tiles is
        // exactly at the half-integer line in this transformed space,
        // so nearest-integer correctly classifies the cursor.
        let ix = Int(fx.rounded())
        let iy = Int(fy.rounded())
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
    /// Tile the user is hovering over with a non-build tool — the
    /// renderer highlights it with a yellow outline so the player sees
    /// exactly what will change on click.
    let hoverHighlight: HoverHighlight?
    let view: IsoMath.ViewTransform

    struct PlacementPreview {
        let kind: String
        let tile: (x: Int, y: Int)
        let valid: Bool
    }

    /// Generic single-tile highlight overlay. `valid` controls whether
    /// the outline is yellow (will act) or red (invalid).
    struct HoverHighlight {
        let x: Int
        let y: Int
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

            // Mountain peaks (tier-2 tiles get a colored pyramid in ground color)
            for y in 0..<state.repo.mapSize {
                for x in 0..<state.repo.mapSize {
                    if state.terrain.elev(x: x, y: y) >= 2 {
                        drawMountainPeak(context: context, x: x, y: y,
                                         biome: biome, canvas: size)
                    }
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

            // Single-tile hover highlight for non-build tools.
            if let hh = hoverHighlight, placementPreview == nil {
                drawTileHighlight(context: context, x: hh.x, y: hh.y,
                                  valid: hh.valid, canvas: size)
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

            // Townsfolk (cardinal interpolation: current → nextStep only).
            // Vanish when entering a building tile or while paused inside
            // one, so they "go inside" rather than visibly crossing the
            // tile's center along an iso diagonal.
            for npc in state.townsfolk {
                let curX = Int(npc.tileX.rounded())
                let curY = Int(npc.tileY.rounded())

                func isBuildingTile(_ x: Int, _ y: Int) -> Bool {
                    state.buildings.contains { b in
                        (x >= b.tileX) && (x < b.tileX + b.width) &&
                            (y >= b.tileY) && (y < b.tileY + b.height)
                    }
                }
                let insideBuilding = isBuildingTile(curX, curY)
                let isPaused = npc.pauseRemaining > 0
                if insideBuilding, isPaused { continue }

                let next = npc.nextStep ?? (curX, curY)
                // If we're about to step into a building tile, fade out
                // partway through the step (the townsfolk "ducks inside"
                // before reaching the destination's center).
                let approachingBuilding = isBuildingTile(next.0, next.1) && !insideBuilding
                if approachingBuilding, phase > 0.5 { continue }

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
                              npc: npc, canvas: size)
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

    /// v3.5 — tree shape varies by biome:
    ///   - tundra / forest: stacked pine cones (3 triangles)
    ///   - desert / beach: palm (trunk + curved fronds)
    ///   - plain: fluffy oak (trunk + 3 overlapping leaf blobs)
    private func drawTreeDecor(context: GraphicsContext, at center: CGPoint,
                               tw: CGFloat, biome: BiomeCatalog.BiomeInfo) {
        let trunkColor = Color(red: 0.34, green: 0.20, blue: 0.12)
        let leafColor: Color = switch biome.biome {
        case .tundra: Color(red: 0.22, green: 0.42, blue: 0.30)
        case .desert: Color(red: 0.42, green: 0.62, blue: 0.36)
        case .beach: Color(red: 0.45, green: 0.72, blue: 0.42)
        case .forest: Color(red: 0.18, green: 0.45, blue: 0.24)
        case .plain: Color(red: 0.28, green: 0.62, blue: 0.30)
        }
        let leafShadow = leafColor.opacity(0.55)

        switch biome.biome {
        case .tundra, .forest:
            // Pine — three stacked triangles.
            let trunkH: CGFloat = tw * 0.22
            let trunk = CGRect(x: center.x - 1.4, y: center.y - trunkH,
                               width: 2.8, height: trunkH)
            context.fill(Path(trunk), with: .color(trunkColor))
            let baseY = center.y - trunkH + 1
            for (i, scale) in [0.95, 0.78, 0.6].enumerated() {
                let layerW = tw * 0.62 * CGFloat(scale)
                let layerH = tw * 0.42 * CGFloat(scale)
                let topY = baseY - layerH * CGFloat(i + 1) * 0.78
                var tri = Path()
                tri.move(to: CGPoint(x: center.x, y: topY - layerH))
                tri.addLine(to: CGPoint(x: center.x + layerW, y: topY + 1))
                tri.addLine(to: CGPoint(x: center.x - layerW, y: topY + 1))
                tri.closeSubpath()
                context.fill(tri, with: .color(i == 0 ? leafShadow : leafColor))
                context.stroke(tri, with: .color(.black.opacity(0.35)),
                               lineWidth: 0.5)
            }

        case .desert, .beach:
            // Palm — trunk with curved fronds.
            let trunkH: CGFloat = tw * 0.55
            let trunk = CGRect(x: center.x - 1.4,
                               y: center.y - trunkH,
                               width: 2.8, height: trunkH)
            context.fill(Path(trunk), with: .color(trunkColor))
            // Trunk segment lines for the palm-rings look.
            for i in 1..<4 {
                let y = center.y - CGFloat(i) * trunkH / 4
                var line = Path()
                line.move(to: CGPoint(x: trunk.minX, y: y))
                line.addLine(to: CGPoint(x: trunk.maxX, y: y))
                context.stroke(line, with: .color(.black.opacity(0.4)),
                               lineWidth: 0.4)
            }
            // Fronds — 5 curved arcs emerging from top.
            let crown = CGPoint(x: center.x, y: center.y - trunkH - 1)
            let frondLen = tw * 0.55
            for angle in stride(from: -.pi * 0.85, through: -.pi * 0.15, by: .pi * 0.175) {
                let endX = crown.x + cos(angle) * frondLen
                let endY = crown.y + sin(angle) * frondLen * 0.55
                let ctrlX = crown.x + cos(angle) * frondLen * 0.4
                let ctrlY = crown.y + sin(angle) * frondLen * 1.2
                var p = Path()
                p.move(to: crown)
                p.addQuadCurve(to: CGPoint(x: endX, y: endY),
                               control: CGPoint(x: ctrlX, y: ctrlY))
                context.stroke(p, with: .color(leafColor), lineWidth: 1.4)
            }
            // Small coconut cluster
            let coconut = CGRect(x: crown.x - 1.6, y: crown.y - 0.5,
                                 width: 3.2, height: 2.2)
            context.fill(Path(ellipseIn: coconut), with: .color(trunkColor))

        case .plain:
            // Oak — short trunk + three overlapping leaf blobs.
            let trunkH: CGFloat = tw * 0.20
            let trunk = CGRect(x: center.x - 1.6,
                               y: center.y - trunkH,
                               width: 3.2, height: trunkH)
            context.fill(Path(trunk), with: .color(trunkColor))
            let crownY = center.y - trunkH
            let r: CGFloat = tw * 0.30
            let blobs = [
                CGPoint(x: center.x - r * 0.6, y: crownY - r * 0.5),
                CGPoint(x: center.x + r * 0.65, y: crownY - r * 0.45),
                CGPoint(x: center.x, y: crownY - r * 1.2),
            ]
            for blob in blobs {
                let rect = CGRect(x: blob.x - r, y: blob.y - r,
                                  width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(leafColor))
            }
            context.stroke(
                Path(ellipseIn: CGRect(x: blobs[0].x - r,
                                       y: blobs[0].y - r,
                                       width: r * 2, height: r * 2)),
                with: .color(.black.opacity(0.3)), lineWidth: 0.5
            )
        }
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

    /// Draws a colored 4-sided pyramid on top of a tier-2 tile, using the
    /// underlying terrain's primary color so the mountain reads as part
    /// of the landscape (a grassy peak / sandy dune / snowfield) instead
    /// of a generic grey rock.
    private func drawMountainPeak(
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
        let peakHeight = IsoMath.elevationOffset(1, zoom: view.zoom) * 1.6

        let groundTile = state.terrain.tile(x: x, y: y)
        let baseColor = groundColor(for: groundTile, biome: biome)
        let apex = CGPoint(x: center.x, y: center.y - peakHeight)
        let cornerN = CGPoint(x: center.x, y: center.y - th)
        let cornerE = CGPoint(x: center.x + tw, y: center.y)
        let cornerS = CGPoint(x: center.x, y: center.y + th)
        let cornerW = CGPoint(x: center.x - tw, y: center.y)

        // Four triangular faces — each a slightly different shade so the
        // pyramid reads as 3D, not as a flat decal.
        for (a, b, shade) in [
            (cornerN, cornerE, 1.0),
            (cornerE, cornerS, 0.78),
            (cornerS, cornerW, 0.86),
            (cornerW, cornerN, 0.92),
        ] {
            var face = Path()
            face.move(to: apex)
            face.addLine(to: a)
            face.addLine(to: b)
            face.closeSubpath()
            context.fill(face, with: .color(baseColor.opacity(shade)))
            context.stroke(face, with: .color(.black.opacity(0.3)), lineWidth: 0.5)
        }
        // Snow cap on tundra so peaks read as "mountains" not just "tall grass."
        if biome.biome == .tundra {
            let snowApexHeight = peakHeight * 0.45
            let snowApex = apex
            let snowBaseW = tw * 0.45
            let snowBaseH = th * 0.45
            let snowCorners = [
                CGPoint(x: center.x, y: center.y - snowBaseH - peakHeight + snowApexHeight),
                CGPoint(x: center.x + snowBaseW, y: center.y - peakHeight + snowApexHeight),
                CGPoint(x: center.x, y: center.y + snowBaseH - peakHeight + snowApexHeight),
                CGPoint(x: center.x - snowBaseW, y: center.y - peakHeight + snowApexHeight),
            ]
            for i in 0..<4 {
                var face = Path()
                face.move(to: snowApex)
                face.addLine(to: snowCorners[i])
                face.addLine(to: snowCorners[(i + 1) % 4])
                face.closeSubpath()
                context.fill(face, with: .color(.white.opacity(0.86)))
            }
        }
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

        // Roads run along the iso axes — between *edge midpoints* of the
        // tile, not between tile corners. So in screen-space a straight
        // road appears as a single diagonal stripe running parallel to
        // the tile's edges (NW↔SE or NE↔SW depending on direction).
        //
        // For each direction the tile connects in (N/E/S/W in tile space,
        // which corresponds to the four edge midpoints on screen), we
        // draw one road "arm" from the tile center to that edge midpoint.
        // Two opposite arms form a straight road; perpendicular arms form
        // a T or cross. Width is perpendicular to the arm.
        let connectsN = (mask & 1) != 0
        let connectsE = (mask & 2) != 0
        let connectsS = (mask & 4) != 0
        let connectsW = (mask & 8) != 0

        // Edge-midpoint offsets from tile center, in screen px.
        let nMid = CGPoint(x: center.x + tw / 2, y: center.y - th / 2)
        let eMid = CGPoint(x: center.x + tw / 2, y: center.y + th / 2)
        let sMid = CGPoint(x: center.x - tw / 2, y: center.y + th / 2)
        let wMid = CGPoint(x: center.x - tw / 2, y: center.y - th / 2)

        // Build a single Path for the asphalt centerline of this tile —
        // either a straight, an L-curve (using a quadratic through the
        // tile center), or one or more arms (Ts, crosses, dead-ends).
        // Then stroke it at the road width. The Path approach gives
        // free smooth L-curves where the previous straight-arm approach
        // had sharp 90° corners.
        let connectionCount = [connectsN, connectsE, connectsS, connectsW].filter { $0 }.count
        let roadWidth: CGFloat = max(4, tw * 0.32)
        let asphaltPath = buildRoadPath(
            center: center,
            connectsN: connectsN, connectsE: connectsE,
            connectsS: connectsS, connectsW: connectsW,
            nMid: nMid, eMid: eMid, sMid: sMid, wMid: wMid
        )
        if connectionCount > 0 {
            context.stroke(asphaltPath,
                           with: .color(asphalt),
                           style: StrokeStyle(lineWidth: roadWidth,
                                              lineCap: .round,
                                              lineJoin: .round))
        }

        // Isolated road tile with no neighbours — paint a small square.
        if connectionCount == 0 {
            let r = roadWidth * 0.45
            let rect = CGRect(x: center.x - r, y: center.y - r,
                              width: r * 2, height: r * 2)
            context.fill(Path(rect), with: .color(asphalt))
        }

        // Yellow dashed lane stripe down the centerline of the same
        // path so all road shapes (straight, L-curve, T, cross,
        // dead-end) get markings.
        let stripeWidth: CGFloat = max(1, roadWidth * 0.13)
        if connectionCount > 0 {
            context.stroke(asphaltPath,
                           with: .color(laneStripeColor),
                           style: StrokeStyle(lineWidth: stripeWidth,
                                              lineCap: .butt,
                                              dash: [4, 3]))
        }

        _ = sidewalk
    }

    /// Construct the centerline `Path` for a road tile given its
    /// connectivity flags. Adjacent-direction pairs (NE / ES / SW / WN)
    /// emit a quadratic curve through the tile center; opposite pairs
    /// (NS / EW) emit a straight line; Ts / crosses / dead-ends emit a
    /// straight arm from the center out to each connecting edge mid.
    private func buildRoadPath(
        center: CGPoint,
        connectsN: Bool, connectsE: Bool, connectsS: Bool, connectsW: Bool,
        nMid: CGPoint, eMid: CGPoint, sMid: CGPoint, wMid: CGPoint
    ) -> Path {
        let total = [connectsN, connectsE, connectsS, connectsW].filter { $0 }.count
        var path = Path()
        // Straight roads — single line through center.
        if total == 2, connectsN, connectsS {
            path.move(to: nMid)
            path.addLine(to: sMid)
            return path
        }
        if total == 2, connectsE, connectsW {
            path.move(to: eMid)
            path.addLine(to: wMid)
            return path
        }
        // L-curves — adjacent pair, quadratic curve through center.
        let lCurves: [(Bool, Bool, CGPoint, CGPoint)] = [
            (connectsN, connectsE, nMid, eMid),
            (connectsE, connectsS, eMid, sMid),
            (connectsS, connectsW, sMid, wMid),
            (connectsW, connectsN, wMid, nMid),
        ]
        if total == 2, let lc = lCurves.first(where: { $0.0 && $0.1 }) {
            path.move(to: lc.2)
            path.addQuadCurve(to: lc.3, control: center)
            return path
        }
        // T / cross / dead-end — straight arms from center to each
        // connecting edge mid.
        let arms: [(Bool, CGPoint)] = [
            (connectsN, nMid), (connectsE, eMid),
            (connectsS, sMid), (connectsW, wMid),
        ]
        for (connect, mid) in arms where connect {
            path.move(to: center)
            path.addLine(to: mid)
        }
        return path
    }


    /// Roads are roads, not biome-themed planks. Dark asphalt + light
    /// concrete sidewalks everywhere; saturation hardly varies between
    /// biomes so the road network reads as infrastructure that crosses
    /// the landscape, not as part of it.
    private func asphaltColor(for biome: BiomeCatalog.BiomeInfo) -> Color {
        _ = biome
        return Color(red: 0.22, green: 0.22, blue: 0.24)
    }

    private func sidewalkColor(for biome: BiomeCatalog.BiomeInfo) -> Color {
        _ = biome
        return Color(red: 0.82, green: 0.82, blue: 0.80)
    }

    private var laneStripeColor: Color {
        Color(red: 0.98, green: 0.85, blue: 0.30)
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

        // Per-archetype extra detail (planks, windows, sails, bell, slats).
        if alpha >= 0.99, let detail = shape.detail {
            drawBuildingDetail(
                context: context, detail: detail,
                center: center, halfW: halfWBase, halfH: halfHBase,
                topCenter: topCenter, halfWTop: halfWTop, halfHTop: halfHTop,
                zoom: zoom
            )
        }

        // Glyph above the roof apex with a soft halo so the meaning is
        // readable against any roof color.
        if alpha >= 0.99 {
            drawRoofGlyph(context: context, glyph: building.glyph, at: topCenter)
        }
    }

    private func drawBuildingDetail(
        context: GraphicsContext,
        detail: BuildingShape.Detail,
        center: CGPoint,
        halfW: CGFloat,
        halfH: CGFloat,
        topCenter: CGPoint,
        halfWTop: CGFloat,
        halfHTop: CGFloat,
        zoom: Double
    ) {
        switch detail {
        case let .planks(plankColor, postColor):
            // Horizontal plank lines across the top face (iso-aligned).
            for f in stride(from: -0.7, through: 0.7, by: 0.18) {
                let frac = CGFloat(f)
                var line = Path()
                line.move(to: CGPoint(x: topCenter.x - halfWTop, y: topCenter.y + halfHTop * frac))
                line.addLine(to: CGPoint(x: topCenter.x + halfWTop, y: topCenter.y + halfHTop * frac))
                context.stroke(line, with: .color(plankColor.opacity(0.5)), lineWidth: 0.6)
            }
            // Posts dropping from each tile-corner under the building down
            // to the tile base (gives the "pier on stilts" silhouette).
            for corner in [
                CGPoint(x: center.x - halfW, y: center.y),
                CGPoint(x: center.x + halfW, y: center.y),
                CGPoint(x: center.x, y: center.y + halfH),
                CGPoint(x: center.x, y: center.y - halfH),
            ] {
                let post = CGRect(x: corner.x - 1.2, y: corner.y,
                                  width: 2.4, height: 4 * CGFloat(zoom))
                context.fill(Path(post), with: .color(postColor))
            }

        case let .windows(rows, columns, color):
            // Small dark squares on the front-left and front-right walls,
            // arranged as a grid. Front-left runs along the southwest wall,
            // front-right along the southeast wall.
            let storyTop = topCenter
            let leftBaseA = CGPoint(x: center.x - halfW, y: center.y)
            let leftBaseB = CGPoint(x: center.x, y: center.y + halfH)
            let rightBaseA = CGPoint(x: center.x + halfW, y: center.y)
            let rightBaseB = leftBaseB
            let leftTopA = CGPoint(x: leftBaseA.x, y: storyTop.y)
            let leftTopB = CGPoint(x: leftBaseB.x, y: storyTop.y)
            let rightTopA = CGPoint(x: rightBaseA.x, y: storyTop.y)
            let rightTopB = CGPoint(x: rightBaseB.x, y: storyTop.y)
            drawWindowGrid(context: context,
                           topA: leftTopA, topB: leftTopB,
                           baseA: leftBaseA, baseB: leftBaseB,
                           rows: rows, columns: columns, color: color)
            drawWindowGrid(context: context,
                           topA: rightTopA, topB: rightTopB,
                           baseA: rightBaseA, baseB: rightBaseB,
                           rows: rows, columns: columns, color: color)

        case let .sails(color):
            // Cross-shaped sails: 4 thin planks pivoted around the
            // building's center, anchored on top of the roof.
            let pivot = CGPoint(x: topCenter.x, y: topCenter.y - 6 * CGFloat(zoom))
            let armLen = max(halfWTop, halfHTop) * 1.05
            let armHalfWidth: CGFloat = 1.6 * CGFloat(zoom)
            for angle in stride(from: 0.0, through: 3 * .pi / 2, by: .pi / 2) {
                let ux = CGFloat(cos(angle + .pi / 6))
                let uy = CGFloat(sin(angle + .pi / 6))
                let px = -uy
                let py = ux
                var sail = Path()
                sail.move(to: CGPoint(x: pivot.x + px * armHalfWidth,
                                      y: pivot.y + py * armHalfWidth))
                sail.addLine(to: CGPoint(x: pivot.x + ux * armLen + px * armHalfWidth,
                                         y: pivot.y + uy * armLen + py * armHalfWidth))
                sail.addLine(to: CGPoint(x: pivot.x + ux * armLen - px * armHalfWidth,
                                         y: pivot.y + uy * armLen - py * armHalfWidth))
                sail.addLine(to: CGPoint(x: pivot.x - px * armHalfWidth,
                                         y: pivot.y - py * armHalfWidth))
                sail.closeSubpath()
                context.fill(sail, with: .color(color.opacity(0.92)))
                context.stroke(sail, with: .color(.black.opacity(0.4)), lineWidth: 0.6)
            }

        case let .bell(color):
            // A small bell suspended over the roof apex.
            let cx = topCenter.x
            let cy = topCenter.y - 6 * CGFloat(zoom)
            let r = 5 * CGFloat(zoom)
            var bell = Path()
            bell.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                        startAngle: .degrees(180), endAngle: .degrees(0),
                        clockwise: false)
            bell.addLine(to: CGPoint(x: cx + r, y: cy + r * 0.3))
            bell.addLine(to: CGPoint(x: cx - r, y: cy + r * 0.3))
            bell.closeSubpath()
            context.fill(bell, with: .color(color))
            context.stroke(bell, with: .color(.black.opacity(0.5)), lineWidth: 0.7)
            // Hanging cord up to the spire
            var cord = Path()
            cord.move(to: CGPoint(x: cx, y: cy - r * 0.4))
            cord.addLine(to: CGPoint(x: cx, y: cy - r * 1.5))
            context.stroke(cord, with: .color(.black.opacity(0.5)), lineWidth: 0.7)

        case let .slats(color):
            // Two or three horizontal stripes across the front face.
            for f in [0.28, 0.5, 0.72] {
                let frac = CGFloat(f)
                let leftBase = CGPoint(x: center.x - halfW, y: center.y)
                let rightBase = CGPoint(x: center.x, y: center.y + halfH)
                let topLine = CGPoint(x: leftBase.x, y: leftBase.y - halfH * (1 - frac))
                let bottomLine = CGPoint(x: rightBase.x, y: rightBase.y - halfH * (1 - frac))
                var line = Path()
                line.move(to: topLine)
                line.addLine(to: bottomLine)
                context.stroke(line, with: .color(color.opacity(0.55)), lineWidth: 0.6)
            }
        }
    }

    private func drawWindowGrid(
        context: GraphicsContext,
        topA: CGPoint, topB: CGPoint,
        baseA: CGPoint, baseB: CGPoint,
        rows: Int, columns: Int, color: Color
    ) {
        // Each window is a small rect placed by bilinearly interpolating
        // between the 4 face corners and shrinking slightly. Reads as a
        // 2D grid on the iso face.
        let r = max(1, rows)
        let c = max(1, columns)
        for row in 0..<r {
            for col in 0..<c {
                let u = (CGFloat(col) + 0.5) / CGFloat(c)
                let v = (CGFloat(row) + 0.5) / CGFloat(r)
                let topPt = CGPoint(x: topA.x + (topB.x - topA.x) * u,
                                    y: topA.y + (topB.y - topA.y) * u)
                let baseP = CGPoint(x: baseA.x + (baseB.x - baseA.x) * u,
                                    y: baseA.y + (baseB.y - baseA.y) * u)
                let p = CGPoint(x: topPt.x + (baseP.x - topPt.x) * v,
                                y: topPt.y + (baseP.y - topPt.y) * v)
                let w: CGFloat = 2.2
                let h: CGFloat = 3.0
                let rect = CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
                context.fill(Path(rect), with: .color(color.opacity(0.85)))
            }
        }
    }

    /// Draws the building's glyph just above its roof apex. v3.3 —
    /// halo dropped (was reading as a UI sticker); glyph smaller so the
    /// building's silhouette wins over the emoji.
    private func drawRoofGlyph(context: GraphicsContext, glyph: String, at top: CGPoint) {
        let zoom = CGFloat(view.zoom)
        let p = CGPoint(x: top.x, y: top.y - 9 * zoom)
        let size = 10 * zoom
        let glyphResolved = context.resolve(Text(glyph).font(.system(size: size)))
        context.draw(glyphResolved, at: p, anchor: .center)
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

    /// Draws a yellow tile outline + soft fill at (x, y). v3.4 — the
    /// indicator is just "this is the tile I'm hovering"; it does not
    /// communicate whether the action will succeed. The action itself
    /// silently no-ops on invalid input (and the cursor moves on
    /// without a confusing red flash).
    private func drawTileHighlight(
        context: GraphicsContext,
        x: Int, y: Int,
        valid _: Bool,
        canvas: CGSize
    ) {
        let elev = state.terrain.elev(x: x, y: y)
        let center = IsoMath.project(x: Double(x), y: Double(y),
                                     elevation: elev,
                                     mapSize: state.repo.mapSize,
                                     canvas: canvas, view: view)
        let tw = IsoMath.tileWidth(forMapSize: state.repo.mapSize, zoom: view.zoom)
        let th = IsoMath.tileHeight(forMapSize: state.repo.mapSize, zoom: view.zoom)
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - th))
        path.addLine(to: CGPoint(x: center.x + tw, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + th))
        path.addLine(to: CGPoint(x: center.x - tw, y: center.y))
        path.closeSubpath()
        let outline = Color(red: 0.98, green: 0.85, blue: 0.30)
        context.fill(path, with: .color(outline.opacity(0.22)))
        context.stroke(path, with: .color(outline), lineWidth: 1.4)
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

    /// v3.5 — paper-doll townsfolk: shirt (hue + pattern), skin head,
    /// hair, optional hat, with a tiny vertical step-bob when walking
    /// (phase ∈ [0, 1)) so people read as moving humans, not dots.
    private func drawTownsfolk(
        context: GraphicsContext,
        x: Double, y: Double, elevation: Int,
        npc: TokeyoTownState.Townsfolk,
        canvas: CGSize
    ) {
        let center = IsoMath.project(x: x, y: y,
                                     elevation: elevation,
                                     mapSize: state.repo.mapSize,
                                     canvas: canvas, view: view)
        let zoom = CGFloat(view.zoom)
        let isWalking = npc.nextStep != nil && npc.pauseRemaining <= 0
        // Tiny vertical bob — two steps per tile (so a leg-swap cadence).
        let bob: CGFloat = isWalking
            ? CGFloat(sin(phase * .pi * 2) * 0.6) * zoom
            : 0

        // Size + proportion vary by age.
        let scaleByAge: CGFloat = switch npc.appearance.ageTier {
        case .child: 0.78
        case .adult: 1.0
        case .elder: 0.92
        }
        let bodyW = 5.0 * zoom * scaleByAge
        let bodyH = 6.5 * zoom * scaleByAge
        let headR = 2.5 * zoom * scaleByAge

        // Anchor point — feet sit on the tile center, body grows upward.
        let feet = CGPoint(x: center.x, y: center.y + bob)
        let bodyRect = CGRect(x: feet.x - bodyW / 2,
                              y: feet.y - bodyH,
                              width: bodyW, height: bodyH)
        let headCenter = CGPoint(x: feet.x, y: bodyRect.minY - headR)
        let headRect = CGRect(x: headCenter.x - headR, y: headCenter.y - headR,
                              width: headR * 2, height: headR * 2)

        let shirtColor = Color(hue: npc.hue, saturation: 0.72, brightness: 0.86)
        let pantsColor = Color(hue: npc.hue,
                               saturation: 0.55,
                               brightness: 0.50)
        let skin = skinColor(tier: npc.appearance.skinTone)
        let hair = Color(hue: npc.appearance.hairHue, saturation: 0.55, brightness: 0.36)

        // Pants (bottom third of body)
        let pantsRect = CGRect(x: bodyRect.minX, y: bodyRect.midY + bodyH * 0.05,
                               width: bodyRect.width, height: bodyH * 0.45)
        context.fill(Path(pantsRect), with: .color(pantsColor))

        // Shirt (top of body)
        let shirtRect = CGRect(x: bodyRect.minX, y: bodyRect.minY,
                               width: bodyRect.width,
                               height: bodyH * 0.62)
        context.fill(Path(shirtRect), with: .color(shirtColor))
        // Shirt pattern overlay.
        drawShirtPattern(context: context, rect: shirtRect,
                         pattern: npc.appearance.pattern, baseHue: npc.hue)

        // Outline around body so paper-doll silhouette stays crisp.
        context.stroke(Path(bodyRect),
                       with: .color(.black.opacity(0.55)),
                       lineWidth: 0.5)

        // Hair tuft (drawn behind head)
        let hairRect = CGRect(x: headRect.minX - 0.3,
                              y: headRect.minY - 0.6,
                              width: headRect.width + 0.6,
                              height: headRect.height * 0.65)
        context.fill(Path(ellipseIn: hairRect), with: .color(hair))

        // Head (skin tone)
        context.fill(Path(ellipseIn: headRect), with: .color(skin))
        context.stroke(Path(ellipseIn: headRect),
                       with: .color(.black.opacity(0.55)), lineWidth: 0.5)

        // Hat
        if npc.appearance.hat != .none {
            drawHat(context: context,
                    head: headRect,
                    kind: npc.appearance.hat,
                    color: Color(hue: npc.appearance.hatHue,
                                 saturation: 0.65, brightness: 0.55))
        }

        // Stepping feet animation — two tiny dots that swap which one is
        // forward each half-phase, drawn only when actively walking.
        if isWalking {
            let stepOffset: CGFloat = CGFloat(sin(phase * .pi * 2)) * 1.5 * zoom
            let footL = CGRect(x: feet.x - bodyW * 0.3 - 0.6 + stepOffset,
                               y: feet.y - 1.4,
                               width: 1.6, height: 1.6)
            let footR = CGRect(x: feet.x + bodyW * 0.3 - 1.0 - stepOffset,
                               y: feet.y - 1.4,
                               width: 1.6, height: 1.6)
            context.fill(Path(footL), with: .color(.black.opacity(0.78)))
            context.fill(Path(footR), with: .color(.black.opacity(0.78)))
        }
    }

    private func drawShirtPattern(
        context: GraphicsContext, rect: CGRect,
        pattern: TokeyoTownState.Townsfolk.Appearance.Pattern,
        baseHue: Double
    ) {
        let accent = Color(hue: (baseHue + 0.5).truncatingRemainder(dividingBy: 1),
                           saturation: 0.72, brightness: 0.92)
        switch pattern {
        case .solid:
            return
        case .stripes:
            // Two thin horizontal stripes
            for f in [0.3, 0.6] {
                let y = rect.minY + rect.height * CGFloat(f)
                var line = Path()
                line.move(to: CGPoint(x: rect.minX, y: y))
                line.addLine(to: CGPoint(x: rect.maxX, y: y))
                context.stroke(line, with: .color(accent.opacity(0.8)),
                               lineWidth: 0.7)
            }
        case .dots:
            for offset in [CGPoint(x: 0.3, y: 0.35), CGPoint(x: 0.7, y: 0.55)] {
                let x = rect.minX + rect.width * CGFloat(offset.x)
                let y = rect.minY + rect.height * CGFloat(offset.y)
                let r: CGFloat = 0.7
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(accent.opacity(0.92)))
            }
        }
    }

    private func skinColor(tier: Int) -> Color {
        switch max(0, min(4, tier)) {
        case 0: return Color(red: 0.98, green: 0.88, blue: 0.78) // pale
        case 1: return Color(red: 0.94, green: 0.80, blue: 0.66)
        case 2: return Color(red: 0.82, green: 0.65, blue: 0.48)
        case 3: return Color(red: 0.62, green: 0.42, blue: 0.28)
        default: return Color(red: 0.42, green: 0.27, blue: 0.18)
        }
    }

    private func drawHat(
        context: GraphicsContext,
        head: CGRect,
        kind: TokeyoTownState.Townsfolk.Appearance.HatKind,
        color: Color
    ) {
        let cx = head.midX
        let topY = head.minY
        switch kind {
        case .none:
            return
        case .round:
            // Half-circle cap.
            var p = Path()
            p.addArc(center: CGPoint(x: cx, y: topY + 0.4),
                     radius: head.width * 0.55,
                     startAngle: .degrees(180), endAngle: .degrees(0),
                     clockwise: false)
            p.closeSubpath()
            context.fill(p, with: .color(color))
            context.stroke(p, with: .color(.black.opacity(0.55)), lineWidth: 0.5)
        case .peaked:
            // Triangle / cone hat.
            var p = Path()
            p.move(to: CGPoint(x: cx, y: topY - head.height * 0.7))
            p.addLine(to: CGPoint(x: head.minX - 0.4, y: topY + 0.4))
            p.addLine(to: CGPoint(x: head.maxX + 0.4, y: topY + 0.4))
            p.closeSubpath()
            context.fill(p, with: .color(color))
            context.stroke(p, with: .color(.black.opacity(0.55)), lineWidth: 0.5)
        case .sunHat:
            // Brim + crown.
            let brimRect = CGRect(x: head.minX - 1.4, y: topY - 0.2,
                                  width: head.width + 2.8, height: 1.4)
            context.fill(Path(ellipseIn: brimRect), with: .color(color))
            let crownRect = CGRect(x: head.minX + head.width * 0.18,
                                   y: topY - head.height * 0.45,
                                   width: head.width * 0.64,
                                   height: head.height * 0.55)
            context.fill(Path(crownRect), with: .color(color))
        case .beanie:
            // Snug cap covering the top of the head.
            var p = Path()
            p.addArc(center: CGPoint(x: cx, y: topY + head.height * 0.32),
                     radius: head.width * 0.55,
                     startAngle: .degrees(180), endAngle: .degrees(0),
                     clockwise: false)
            p.closeSubpath()
            context.fill(p, with: .color(color))
            // Pom-pom dot
            let pomRect = CGRect(x: cx - 0.8, y: topY - 1.2, width: 1.6, height: 1.6)
            context.fill(Path(ellipseIn: pomRect), with: .color(.white.opacity(0.92)))
        }
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

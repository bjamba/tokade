import Foundation

/// Lays down a starter town when a new town is created. The player begins
/// with zero resources, but the world isn't empty — a few seed buildings
/// + roads + townsfolk are placed for free, based on the repo's
/// characteristics. Players can demolish/terraform anything they don't
/// want, since v3 introduced the undo stack and a universal remove tool.
enum InitialTownPlanner {
    /// Mutates the given state in place to add starter buildings, roads,
    /// and townsfolk. Existing buildings/townsfolk are preserved (this
    /// function is also safe to call multiple times — it just won't
    /// duplicate placements).
    static func preSeed(state: inout TokeyoTownState, scan: RepoScanner.ScanResult) {
        let biome = state.repo.biome
        let mapSize = state.terrain.size
        let allowed: Set<TerrainTile> = (biome == .beach || biome == .desert)
            ? [.grass, .sand] : [.grass]

        // 1. Find an "anchor" tile — somewhere near the centre with
        //    enough buildable space around it for our seed cluster.
        let center = (mapSize / 2, mapSize / 2)
        guard let anchor = findClusterAnchor(
            near: center, mapSize: mapSize,
            terrain: state.terrain, allowed: allowed,
            existing: state.buildings
        ) else { return }

        // 2. Choose home variants for this biome and place one per
        //    contributor (capped). The contributor count from the scan
        //    is how many people lived in the repo; that maps nicely to
        //    a small starter neighbourhood.
        let homeVariants = BuildingCatalog.buildings(for: biome).filter(\.isHome)
        let homesToPlace = min(max(2, scan.contributorCount), 5)
        var placements: [(x: Int, y: Int, building: BuildingCatalog.Building)] = []

        var seedRng = SplitMix64(seed: TerrainGenerator.seed(for: state.townId) &+ 7)

        for i in 0..<homesToPlace {
            guard let home = homeVariants.randomChoice(rng: &seedRng) else { break }
            let offset = ringOffset(index: i, ring: 1)
            let tx = anchor.0 + offset.0
            let ty = anchor.1 + offset.1
            if tryPlace(at: tx, y: ty, building: home,
                         mapSize: mapSize, terrain: state.terrain,
                         allowed: allowed, placed: placements) {
                placements.append((tx, ty, home))
            }
        }

        // 3. Repo-specific landmark seeds.
        if scan.hasTestsDir, let school = byId("plain-school", biome: biome)
            ?? byBiome(.school, biome: biome) {
            tryPlaceNear(building: school, near: anchor, ring: 2,
                         mapSize: mapSize, terrain: state.terrain,
                         allowed: allowed, into: &placements,
                         rng: &seedRng)
        }
        if scan.hasDocsDir || scan.hasReadme, let lib = byBiome(.library, biome: biome) {
            tryPlaceNear(building: lib, near: anchor, ring: 2,
                         mapSize: mapSize, terrain: state.terrain,
                         allowed: allowed, into: &placements,
                         rng: &seedRng)
        }
        if scan.hasCi, let workshop = byBiome(.workshop, biome: biome) {
            tryPlaceNear(building: workshop, near: anchor, ring: 2,
                         mapSize: mapSize, terrain: state.terrain,
                         allowed: allowed, into: &placements,
                         rng: &seedRng)
        }

        // 4. Commit placements (free — no cost deducted).
        for p in placements {
            state.buildings.append(.init(
                id: UUID(),
                kind: p.building.id,
                tileX: p.x, tileY: p.y,
                width: p.building.shape.footprint.w,
                height: p.building.shape.footprint.h,
                placedAt: .now
            ))
        }

        // 5. Roads connecting every placement back to the anchor.
        for p in placements {
            paintRoadLine(
                from: anchor, to: (p.x, p.y),
                terrain: &state.terrain, mapSize: mapSize,
                buildings: state.buildings
            )
        }

        // 6. Townsfolk — one per home placement, plus one extra.
        let homePlacements = placements.filter { p in p.building.isHome }
        for p in homePlacements {
            guard let last = state.buildings.last(where: {
                $0.tileX == p.x && $0.tileY == p.y && $0.kind == p.building.id
            }) else { continue }
            if let npc = TownsfolkSpawner.spawnOne(
                biome: biome, terrain: state.terrain, home: last
            ) {
                state.townsfolk.append(npc)
            }
        }
        // Plus a wanderer or two for atmosphere.
        let extras = TownsfolkSpawner.spawn(
            count: max(1, scan.contributorCount / 3),
            biome: biome, terrain: state.terrain
        )
        state.townsfolk.append(contentsOf: extras)
    }

    // MARK: - Internals

    /// Walks outward from `near` looking for a tile with enough
    /// surrounding buildable tiles. Returns the centre of the cluster.
    private static func findClusterAnchor(
        near: (Int, Int),
        mapSize: Int,
        terrain: TerrainGrid,
        allowed: Set<TerrainTile>,
        existing: [TokeyoTownState.PlacedBuilding]
    ) -> (Int, Int)? {
        let maxR = mapSize / 2
        for r in 0...maxR {
            for dy in -r...r {
                for dx in -r...r where abs(dx) == r || abs(dy) == r {
                    let x = near.0 + dx
                    let y = near.1 + dy
                    guard terrain.contains(x: x, y: y) else { continue }
                    if allowed.contains(terrain.tile(x: x, y: y)),
                        terrain.elev(x: x, y: y) == 0,
                        !existing.contains(where: { $0.tileX == x && $0.tileY == y }) {
                        return (x, y)
                    }
                }
            }
        }
        return nil
    }

    /// Eight neighbour offsets at the given chess-king ring distance.
    /// Index 0..7 cycles through the ring in clockwise order.
    private static func ringOffset(index: Int, ring: Int) -> (Int, Int) {
        let r = ring
        let directions: [(Int, Int)] = [
            (r, 0), (r, r), (0, r), (-r, r),
            (-r, 0), (-r, -r), (0, -r), (r, -r),
        ]
        return directions[index % directions.count]
    }

    private static func tryPlace(
        at x: Int, y: Int,
        building b: BuildingCatalog.Building,
        mapSize: Int,
        terrain: TerrainGrid,
        allowed: Set<TerrainTile>,
        placed: [(x: Int, y: Int, building: BuildingCatalog.Building)]
    ) -> Bool {
        let fp = b.shape.footprint
        guard terrain.canBuild(at: x, y: y, w: fp.w, h: fp.h, allowedTiles: allowed)
        else { return false }
        // No overlap with our own previous placements.
        for p in placed {
            let pfp = p.building.shape.footprint
            if x < p.x + pfp.w, x + fp.w > p.x,
               y < p.y + pfp.h, y + fp.h > p.y { return false }
        }
        _ = mapSize
        return true
    }

    private static func tryPlaceNear(
        building b: BuildingCatalog.Building,
        near: (Int, Int),
        ring: Int,
        mapSize: Int,
        terrain: TerrainGrid,
        allowed: Set<TerrainTile>,
        into placements: inout [(x: Int, y: Int, building: BuildingCatalog.Building)],
        rng: inout SplitMix64
    ) {
        // Try all 8 positions on the ring in random order.
        var indices = Array(0..<8)
        indices.shuffle(rng: &rng)
        for i in indices {
            let offset = ringOffset(index: i, ring: ring)
            let x = near.0 + offset.0
            let y = near.1 + offset.1
            if tryPlace(at: x, y: y, building: b, mapSize: mapSize,
                        terrain: terrain, allowed: allowed, placed: placements) {
                placements.append((x, y, b))
                return
            }
        }
    }

    /// Paint road tiles in an L-shape between two tile coords. Skips
    /// any tiles that aren't road-paintable (water, rock, building
    /// footprint, peaks).
    private static func paintRoadLine(
        from a: (Int, Int), to b: (Int, Int),
        terrain: inout TerrainGrid,
        mapSize: Int,
        buildings: [TokeyoTownState.PlacedBuilding]
    ) {
        _ = mapSize
        let occupied: Set<Pair> = Set(buildings.flatMap { b -> [Pair] in
            (b.tileX..<b.tileX + b.width).flatMap { x in
                (b.tileY..<b.tileY + b.height).map { y in Pair(x: x, y: y) }
            }
        })
        var x = a.0
        var y = a.1
        // Horizontal then vertical.
        while x != b.0 {
            x += (b.0 > x) ? 1 : -1
            paintRoad(x: x, y: y, terrain: &terrain, occupied: occupied)
        }
        while y != b.1 {
            y += (b.1 > y) ? 1 : -1
            paintRoad(x: x, y: y, terrain: &terrain, occupied: occupied)
        }
    }

    private struct Pair: Hashable { let x: Int; let y: Int }

    private static func paintRoad(
        x: Int, y: Int,
        terrain: inout TerrainGrid,
        occupied: Set<Pair>
    ) {
        guard terrain.contains(x: x, y: y) else { return }
        if occupied.contains(Pair(x: x, y: y)) { return }
        let t = terrain.tile(x: x, y: y)
        guard t == .grass || t == .sand || t == .flower else { return }
        guard terrain.elev(x: x, y: y) < 2 else { return }
        terrain.setTile(.road, x: x, y: y)
    }

    // MARK: - Building lookup by signal

    /// Coarse "role" lookups so we don't hardcode IDs per biome.
    enum BuildingRole { case school, library, workshop }

    private static func byBiome(_ role: BuildingRole,
                                biome: TokeyoTownState.Biome) -> BuildingCatalog.Building? {
        let all = BuildingCatalog.buildings(for: biome)
        switch role {
        case .school:
            return all.first(where: { ["plain-school"].contains($0.id) })
                ?? all.first(where: { $0.id.contains("school") })
        case .library:
            return all.first(where: { $0.id.contains("library") })
                ?? all.first(where: { $0.id.contains("observatory") })
        case .workshop:
            return all.first(where: { $0.id.contains("forge") })
                ?? all.first(where: { $0.id.contains("mill") })
                ?? all.first(where: { $0.id.contains("windmill") })
                ?? all.first(where: { $0.id.contains("market") })
        }
    }

    private static func byId(_ id: String, biome: TokeyoTownState.Biome) -> BuildingCatalog.Building? {
        let b = BuildingCatalog.find(id)
        return b?.biome == biome ? b : nil
    }
}

// MARK: - Random helpers

private extension Array {
    mutating func shuffle(rng: inout SplitMix64) {
        guard count > 1 else { return }
        for i in stride(from: count - 1, through: 1, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            swapAt(i, j)
        }
    }

    func randomChoice(rng: inout SplitMix64) -> Element? {
        guard !isEmpty else { return nil }
        return self[Int(rng.next() % UInt64(count))]
    }
}

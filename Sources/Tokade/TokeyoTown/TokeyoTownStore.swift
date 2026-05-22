import Foundation
import Observation
import os.log

/// Owns the live Tokeyo Town state.
@MainActor
@Observable
final class TokeyoTownStore {
    private(set) var state: TokeyoTownState?
    private(set) var index: TokeyoTownIndex = .empty

    /// Currently-selected tool (what tapping a tile will do).
    var tool: Tool = .hand

    /// Camera view transform — scrubbed in the UI by zoom buttons + drag.
    var view: IsoMath.ViewTransform = .identity

    enum Tool: Equatable, Hashable {
        case hand                  // universal Remove — buildings, trees, rocks, flowers, roads, decor
        case pan                   // drag the camera
        case build(String)         // place a building
        case road                  // paint a road tile
        case plantTree             // plant a tree
        case plantFlower           // place a flower
        case lantern               // place a decoration lantern
        case pond                  // place a water tile (build your own ponds / park lakes)
        case raise                 // raise terrain one tier (max +2)
        case lower                 // lower terrain one tier (min -1)

        var displayName: String {
            switch self {
            case .hand: return "Remove"
            case .pan: return "Pan"
            case let .build(id):
                return BuildingCatalog.find(id)?.displayName ?? "Build"
            case .road: return "Road"
            case .plantTree: return "Plant Tree"
            case .plantFlower: return "Plant Flower"
            case .lantern: return "Lantern"
            case .pond: return "Pond"
            case .raise: return "Raise"
            case .lower: return "Lower"
            }
        }

        var glyph: String {
            switch self {
            case .hand: return "🗑"
            case .pan: return "✥"
            case let .build(id): return BuildingCatalog.find(id)?.glyph ?? "🏠"
            case .road: return "🛣"
            case .plantTree: return "🌳"
            case .plantFlower: return "🌸"
            case .lantern: return "🏮"
            case .pond: return "💧"
            case .raise: return "⛰"
            case .lower: return "🕳"
            }
        }
    }

    // MARK: - Action costs (centralized)

    static let roadCost = TokeyoTownState.Resources(coin: 4)
    static let clearTreeCost = TokeyoTownState.Resources(coin: 8)
    static let clearTreeRefund = TokeyoTownState.Resources(lumber: 4)
    static let plantTreeCost = TokeyoTownState.Resources(lumber: 6)
    static let levelRockCost = TokeyoTownState.Resources(industry: 10)
    static let plantFlowerCost = TokeyoTownState.Resources(growth: 3)
    static let lanternCost = TokeyoTownState.Resources(coin: 12)
    /// Pond: paint a water tile on grass/sand. Cheap so players can use
    /// it to compose "parks" of any size + shape from water + flowers
    /// + trees + lanterns, without needing a dedicated park building.
    static let pondCost = TokeyoTownState.Resources(coin: 10)
    // v3.2 — terrain shaping now costs coin so it's accessible from day
    // one (industry is one of the slowest-earning resources).
    static let raiseCost = TokeyoTownState.Resources(coin: 30)
    static let lowerCost = TokeyoTownState.Resources(coin: 30)

    // MARK: - Undo / redo

    private static let historyCap = 50
    private var undoStack: [TokeyoTownState] = []
    private var redoStack: [TokeyoTownState] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Save plumbing

    private let save = TokeyoTownSave()
    private let log = Logger(subsystem: "com.bjamba.tokade", category: "TokeyoTown")
    private var dirty = false
    private var lastWriteAt: Date = .distantPast

    init() {}

    func load() async {
        index = await save.readIndex()
        state = await save.readActiveTown()
    }

    // MARK: - Town lifecycle

    func startNewTown(at path: URL, scan: RepoScanner.ScanResult, now: Date = .now) async {
        if let oldId = index.activeTownId {
            await save.archiveTown(id: oldId)
        }
        let townId = RepoScanner.townId(for: path)
        let repo = TokeyoTownState.RepoSnapshot(
            path: scan.path.path,
            displayName: scan.displayName,
            scannedAt: now,
            primaryLanguage: scan.primaryLanguage,
            biome: scan.biome,
            era: scan.era,
            ageInDays: scan.ageInDays,
            loc: scan.loc,
            mapSize: scan.mapSize,
            contributorCount: scan.contributorCount,
            lushness: scan.lushness
        )
        var fresh = TokeyoTownState.fresh(townId: townId, repo: repo, now: now)
        // v3.5 — pre-seed the town with a few starter buildings, roads,
        // and townsfolk based on the repo's characteristics. Free
        // placements (no resource deduction); player still starts at 0.
        InitialTownPlanner.preSeed(state: &fresh, scan: scan)
        // v3.6 — seed the resource high-water mark to "now" so only
        // events that arrive AFTER the town is created accrue. Without
        // this a fresh town processes every historical UsageEvent
        // (months of Claude history → millions of tokens → coin tsunami).
        fresh.accountedEvents.lastTimestamp = now
        fresh.accountedEvents.lastEventId = nil
        // And explicitly zero resources in case anything slipped in.
        fresh.resources = .zero
        undoStack.removeAll()
        redoStack.removeAll()
        state = fresh
        index = TokeyoTownIndex(
            activeTownId: townId,
            towns: [.init(
                townId: townId, displayName: repo.displayName,
                repoPath: repo.path, biome: repo.biome,
                lastOpenedAt: now
            )]
        )
        await save.writeTown(fresh)
        await save.writeIndex(index)
    }

    func eraseAll() async {
        await save.eraseAll()
        state = nil
        index = .empty
        undoStack.removeAll()
        redoStack.removeAll()
    }

    // MARK: - Tools

    func selectTool(_ tool: Tool) {
        self.tool = tool
    }

    func selectBuilding(_ kind: String?) {
        tool = kind.map { .build($0) } ?? .hand
    }

    var pendingPlacement: String? {
        if case let .build(id) = tool { return id }
        return nil
    }

    // MARK: - Placement validation

    private func allowedBuildTiles(_ biome: TokeyoTownState.Biome) -> Set<TerrainTile> {
        switch biome {
        case .beach, .desert: return [.grass, .sand]
        default: return [.grass]
        }
    }

    func canPlaceBuilding(_ kind: String, at x: Int, y: Int) -> Bool {
        guard let s = state, let b = BuildingCatalog.find(kind), b.biome == s.repo.biome else { return false }
        let fp = b.shape.footprint

        // Water-extending buildings (piers) have a special rule: footprint
        // must straddle water AND land. Elevation matching is skipped.
        if b.extendsIntoWater {
            guard x >= 0, y >= 0,
                  x + fp.w <= s.terrain.size, y + fp.h <= s.terrain.size else { return false }
            var sawWater = false
            var sawLand = false
            for dy in 0..<fp.h {
                for dx in 0..<fp.w {
                    let t = s.terrain.tile(x: x + dx, y: y + dy)
                    if t == .water {
                        sawWater = true
                    } else if allowedBuildTiles(s.repo.biome).contains(t) {
                        sawLand = true
                    } else {
                        return false
                    }
                }
            }
            guard sawWater, sawLand else { return false }
        } else {
            guard s.terrain.canBuild(at: x, y: y, w: fp.w, h: fp.h,
                                    allowedTiles: allowedBuildTiles(s.repo.biome)) else { return false }
        }

        for existing in s.buildings {
            if rectsOverlap(
                ax: existing.tileX, ay: existing.tileY,
                aw: existing.width, ah: existing.height,
                bx: x, by: y, bw: fp.w, bh: fp.h
            ) { return false }
        }
        return s.resources.canAfford(b.cost)
    }

    // MARK: - Apply tool

    @discardableResult
    func applyToolAt(x: Int, y: Int) async -> Bool {
        guard let s = state else { return false }
        return switch tool {
        case .pan:
            false // pan is purely a camera-drag mode; taps do nothing
        case .hand:
            await handAction(state: s, x: x, y: y)
        case let .build(id):
            await placeBuildingAction(id: id, x: x, y: y)
        case .road:
            await placeRoadAction(x: x, y: y)
        case .plantTree:
            await terraformAction(x: x, y: y, requireTile: .grass, replacement: .tree,
                                  cost: Self.plantTreeCost, refund: .zero)
        case .plantFlower:
            await terraformAction(x: x, y: y, requireTile: .grass, replacement: .flower,
                                            cost: Self.plantFlowerCost, refund: .zero)
        case .lantern:
            await terraformAction(x: x, y: y, requireTile: .grass, replacement: .decor,
                                  cost: Self.lanternCost, refund: .zero)
        case .pond:
            await pondAction(x: x, y: y)
        case .raise:
            await raiseAction(x: x, y: y)
        case .lower:
            await lowerAction(x: x, y: y)
        }
    }

    // MARK: - Individual actions (each takes a snapshot before mutating)

    private func snapshot() {
        guard let s = state else { return }
        undoStack.append(s)
        if undoStack.count > Self.historyCap { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// v3.6 — universal Remove. Demolishes whatever's on the tile and
    /// refunds the resources that were spent placing it.
    ///   - Building: full refund of its cost.
    ///   - Tree: refund the plant-tree cost (6 lumber).
    ///   - Flower: refund the plant-flower cost (3 growth).
    ///   - Lantern decor: refund the lantern cost (12 coin).
    ///   - Road: refund the road cost (4 coin).
    ///   - Rock: no refund (terrain, not player-placed) — replaced with
    ///           grass at the tile's current elevation.
    private func handAction(state s: TokeyoTownState, x: Int, y: Int) async -> Bool {
        // Building first — taps inside a footprint always demolish.
        if let hit = s.buildings.first(where: { b in
            (x >= b.tileX) && (x < b.tileX + b.width) &&
                (y >= b.tileY) && (y < b.tileY + b.height)
        }) {
            snapshot()
            var ns = s
            ns.buildings.removeAll { $0.id == hit.id }
            ns.townsfolk = ns.townsfolk.map { npc in
                var n = npc
                if n.homeBuildingId == hit.id { n.homeBuildingId = nil }
                return n
            }
            if let b = BuildingCatalog.find(hit.kind) {
                ns.resources.add(b.cost)
            }
            state = ns
            await flush()
            return true
        }

        let tile = s.terrain.tile(x: x, y: y)
        let refund: TokeyoTownState.Resources
        let restoreElevation: Bool
        switch tile {
        case .tree: refund = Self.plantTreeCost; restoreElevation = false
        case .flower: refund = Self.plantFlowerCost; restoreElevation = false
        case .decor: refund = Self.lanternCost; restoreElevation = false
        case .road: refund = Self.roadCost; restoreElevation = false
        case .rock: refund = .zero; restoreElevation = false
        case .water:
            // Player-painted ponds (elev was lowered to -1) refund the
            // pond cost. Naturally-generated water at the map edges
            // doesn't — but we have no way to distinguish, so we refund
            // the pond cost either way. Cheap enough not to break.
            refund = Self.pondCost; restoreElevation = true
        default: return false
        }
        snapshot()
        var ns = s
        ns.terrain.setTile(.grass, x: x, y: y)
        if restoreElevation, ns.terrain.elev(x: x, y: y) < 0 {
            ns.terrain.setElev(0, x: x, y: y)
        }
        ns.resources.add(refund)
        state = ns
        await flush()
        return true
    }

    /// Place a water tile on grass/sand at elevation 0, dropping it to
    /// elevation -1. Players use this to compose ponds and "lake parks"
    /// at any size.
    private func pondAction(x: Int, y: Int) async -> Bool {
        guard var s = state, s.terrain.contains(x: x, y: y) else { return false }
        let t = s.terrain.tile(x: x, y: y)
        guard t == .grass || t == .sand || t == .flower else { return false }
        guard s.terrain.elev(x: x, y: y) == 0 else { return false }
        guard s.resources.canAfford(Self.pondCost) else { return false }
        snapshot()
        _ = s.resources.deduct(Self.pondCost)
        s.terrain.setTile(.water, x: x, y: y)
        s.terrain.setElev(-1, x: x, y: y)
        state = s
        await flush()
        return true
    }

    private func placeBuildingAction(id: String, x: Int, y: Int) async -> Bool {
        guard canPlaceBuilding(id, at: x, y: y),
              let b = BuildingCatalog.find(id),
              var s = state else { return false }
        snapshot()
        _ = s.resources.deduct(b.cost)
        let placed = TokeyoTownState.PlacedBuilding(
            id: UUID(), kind: id, tileX: x, tileY: y,
            width: b.shape.footprint.w, height: b.shape.footprint.h,
            placedAt: .now
        )
        s.buildings.append(placed)
        if isHomeBuilding(id) {
            s.townsfolk = TownsfolkSpawner.assignHomeIfNeeded(s.townsfolk, to: placed)
            if Double.random(in: 0..<1) < 0.5,
               let newcomer = TownsfolkSpawner.spawnOne(
                   biome: s.repo.biome, terrain: s.terrain, home: placed
               ) {
                s.townsfolk.append(newcomer)
            }
        }
        state = s
        await flush()
        return true
    }

    private func isHomeBuilding(_ id: String) -> Bool {
        BuildingCatalog.find(id)?.isHome ?? false
    }

    private func placeRoadAction(x: Int, y: Int) async -> Bool {
        guard var s = state, s.terrain.contains(x: x, y: y) else { return false }
        let current = s.terrain.tile(x: x, y: y)
        guard current == .grass || current == .sand || current == .flower else { return false }
        // No roads on mountain peaks — we don't yet have angled road
        // graphics for elevation changes, so roads stay on flat tiles.
        guard s.terrain.elev(x: x, y: y) < 2 else { return false }
        guard s.resources.canAfford(Self.roadCost) else { return false }
        snapshot()
        _ = s.resources.deduct(Self.roadCost)
        s.terrain.setTile(.road, x: x, y: y)
        state = s
        await flush()
        return true
    }

    private func terraformAction(
        x: Int, y: Int,
        requireTile: TerrainTile, replacement: TerrainTile,
        cost: TokeyoTownState.Resources, refund: TokeyoTownState.Resources,
        alsoZeroElevation: Bool = false
    ) async -> Bool {
        guard var s = state, s.terrain.contains(x: x, y: y) else { return false }
        guard s.terrain.tile(x: x, y: y) == requireTile else { return false }
        guard s.resources.canAfford(cost) else { return false }
        snapshot()
        _ = s.resources.deduct(cost)
        s.resources.add(refund)
        s.terrain.setTile(replacement, x: x, y: y)
        if alsoZeroElevation {
            s.terrain.setElev(0, x: x, y: y)
        }
        state = s
        await flush()
        return true
    }

    private func raiseAction(x: Int, y: Int) async -> Bool {
        guard var s = state, s.terrain.contains(x: x, y: y) else { return false }
        let current = s.terrain.elev(x: x, y: y)
        // v3.8 — elev max bumped to 4 so players can build proper
        // mountain ranges, not a single peak tier.
        guard current < 4 else { return false }
        if isOccupiedByBuilding(x: x, y: y) { return false }
        // Roads can't survive an elevation change without angled-road
        // graphics — reject the raise rather than silently break them.
        if s.terrain.tile(x: x, y: y) == .road { return false }
        guard s.resources.canAfford(Self.raiseCost) else { return false }
        snapshot()
        _ = s.resources.deduct(Self.raiseCost)
        s.terrain.setElev(current + 1, x: x, y: y)
        // v3.1 — raising water becomes grass/sand, but raising grass
        // does NOT convert to rock. The terrain kind stays the same and
        // the renderer draws a pyramid in the ground color at tier 2.
        if s.terrain.tile(x: x, y: y) == .water {
            // Surface tile lifted out of water — biome decides what's exposed.
            s.terrain.setTile(s.repo.biome == .desert ? .sand : .grass, x: x, y: y)
        }
        state = s
        await flush()
        return true
    }

    private func lowerAction(x: Int, y: Int) async -> Bool {
        guard var s = state, s.terrain.contains(x: x, y: y) else { return false }
        let current = s.terrain.elev(x: x, y: y)
        // v3.8 — Lower stops at flat ground (elev 0). Use the Pond
        // tool to create water tiles; Lower is purely for sculpting
        // mountains/hills back down.
        guard current > 0 else { return false }
        if isOccupiedByBuilding(x: x, y: y) { return false }
        if s.terrain.tile(x: x, y: y) == .road { return false }
        guard s.resources.canAfford(Self.lowerCost) else { return false }
        snapshot()
        _ = s.resources.deduct(Self.lowerCost)
        s.terrain.setElev(current - 1, x: x, y: y)
        state = s
        await flush()
        return true
    }

    private func isOccupiedByBuilding(x: Int, y: Int) -> Bool {
        guard let s = state else { return false }
        return s.buildings.contains { b in
            (x >= b.tileX) && (x < b.tileX + b.width) &&
                (y >= b.tileY) && (y < b.tileY + b.height)
        }
    }

    // MARK: - Undo / Redo

    func undo() async {
        guard let previous = undoStack.popLast(), let current = state else { return }
        redoStack.append(current)
        state = previous
        dirty = true
        await flush()
    }

    func redo() async {
        guard let next = redoStack.popLast(), let current = state else { return }
        undoStack.append(current)
        state = next
        dirty = true
        await flush()
    }

    private func rectsOverlap(
        ax: Int, ay: Int, aw: Int, ah: Int,
        bx: Int, by: Int, bw: Int, bh: Int
    ) -> Bool {
        ax < bx + bw && ax + aw > bx &&
            ay < by + bh && ay + ah > by
    }

    // MARK: - Tick

    func tick(against events: [UsageEvent]) async {
        guard var s = state else { return }
        let currentCwd = events.last(where: { $0.cwd != nil })?.cwd
        let (delta, newAccounted) = ResourceAccrual.accrue(
            events: events,
            repoPath: s.repo.path,
            accounted: s.accountedEvents,
            currentSessionCwd: currentCwd
        )
        s.resources.add(delta)
        s.accountedEvents = newAccounted
        s.lastTickAt = .now
        s.townsfolk = TownsfolkAI.step(
            townsfolk: s.townsfolk,
            buildings: s.buildings,
            terrain: s.terrain,
            mapSize: s.repo.mapSize
        )
        state = s
        scheduleWrite()
    }

    // MARK: - Camera

    func zoomIn() {
        let zooms = IsoMath.ViewTransform.allZooms
        if let i = zooms.firstIndex(of: view.zoom), i + 1 < zooms.count {
            view.zoom = zooms[i + 1]
        }
    }

    func zoomOut() {
        let zooms = IsoMath.ViewTransform.allZooms
        if let i = zooms.firstIndex(of: view.zoom), i > 0 {
            view.zoom = zooms[i - 1]
        }
    }

    func recenterCamera() {
        view = .identity
    }

    func pan(by delta: CGSize) {
        view.panX += delta.width
        view.panY += delta.height
    }

    // MARK: - Write debounce

    private func scheduleWrite() {
        dirty = true
        let now = Date.now
        if now.timeIntervalSince(lastWriteAt) > 5 {
            Task { await flush() }
        }
    }

    private func flush() async {
        guard let s = state, dirty else { return }
        await save.writeTown(s)
        var idx = index
        if let entryIndex = idx.towns.firstIndex(where: { $0.townId == s.townId }) {
            idx.towns[entryIndex].lastOpenedAt = .now
            await save.writeIndex(idx)
            index = idx
        }
        dirty = false
        lastWriteAt = .now
    }
}

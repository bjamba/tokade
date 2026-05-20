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
        case hand                  // demolish building OR clear flower/decor — the universal "remove" tool
        case pan                   // drag the camera instead of acting on tiles
        case build(String)         // place this building id
        case road                  // paint a road tile
        case clearTree
        case plantTree
        case levelRock
        case plantFlower
        case lantern
        case raise                 // raise terrain one tier (max +2)
        case lower                 // lower terrain one tier (min -1)

        /// Human-readable name used by the current-tool indicator.
        var displayName: String {
            switch self {
            case .hand: return "Remove"
            case .pan: return "Pan"
            case let .build(id):
                return BuildingCatalog.find(id)?.displayName ?? "Build"
            case .road: return "Road"
            case .clearTree: return "Fell Tree"
            case .plantTree: return "Plant Tree"
            case .levelRock: return "Level Rock"
            case .plantFlower: return "Plant Flower"
            case .lantern: return "Lantern"
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
            case .clearTree: return "🪓"
            case .plantTree: return "🌱"
            case .levelRock: return "⛏"
            case .plantFlower: return "🌸"
            case .lantern: return "🏮"
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
        fresh.townsfolk = TownsfolkSpawner.spawn(
            count: min(repo.contributorCount + 1, 6),
            biome: repo.biome,
            terrain: fresh.terrain,
            now: now
        )
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

    /// Pier (and any other water-adjacency-required building) must touch water.
    private static let waterAdjacentBuildings: Set<String> = ["beach-pier"]

    func canPlaceBuilding(_ kind: String, at x: Int, y: Int) -> Bool {
        guard let s = state, let b = BuildingCatalog.find(kind), b.biome == s.repo.biome else { return false }
        let fp = b.shape.footprint
        guard s.terrain.canBuild(at: x, y: y, w: fp.w, h: fp.h,
                                 allowedTiles: allowedBuildTiles(s.repo.biome)) else { return false }
        for existing in s.buildings {
            if rectsOverlap(
                ax: existing.tileX, ay: existing.tileY,
                aw: existing.width, ah: existing.height,
                bx: x, by: y, bw: fp.w, bh: fp.h
            ) { return false }
        }
        if Self.waterAdjacentBuildings.contains(kind),
           !footprintTouchesWater(at: x, y: y, w: fp.w, h: fp.h, terrain: s.terrain) {
            return false
        }
        return s.resources.canAfford(b.cost)
    }

    private func footprintTouchesWater(at x: Int, y: Int, w: Int, h: Int, terrain: TerrainGrid) -> Bool {
        for dy in 0..<h {
            for dx in 0..<w {
                let nx = x + dx
                let ny = y + dy
                if terrain.tile(x: nx - 1, y: ny) == .water { return true }
                if terrain.tile(x: nx + 1, y: ny) == .water { return true }
                if terrain.tile(x: nx, y: ny - 1) == .water { return true }
                if terrain.tile(x: nx, y: ny + 1) == .water { return true }
            }
        }
        return false
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
        case .clearTree:
            await terraformAction(x: x, y: y, requireTile: .tree, replacement: .grass,
                                            cost: Self.clearTreeCost, refund: Self.clearTreeRefund)
        case .plantTree:
            await terraformAction(x: x, y: y, requireTile: .grass, replacement: .tree,
                                            cost: Self.plantTreeCost, refund: .zero)
        case .levelRock:
            await terraformAction(x: x, y: y, requireTile: .rock, replacement: .grass,
                                            cost: Self.levelRockCost, refund: .zero,
                                            alsoZeroElevation: true)
        case .plantFlower:
            await terraformAction(x: x, y: y, requireTile: .grass, replacement: .flower,
                                            cost: Self.plantFlowerCost, refund: .zero)
        case .lantern:
            await terraformAction(x: x, y: y, requireTile: .grass, replacement: .decor,
                                            cost: Self.lanternCost, refund: .zero)
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

    private func handAction(state s: TokeyoTownState, x: Int, y: Int) async -> Bool {
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
            state = ns
            await flush()
            return true
        }
        let tile = s.terrain.tile(x: x, y: y)
        // Hand also clears anything paintable (flower, decor, road).
        if tile == .flower || tile == .decor || tile == .road {
            snapshot()
            var ns = s
            ns.terrain.setTile(.grass, x: x, y: y)
            state = ns
            await flush()
            return true
        }
        return false
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
        guard current < 2 else { return false }
        if isOccupiedByBuilding(x: x, y: y) { return false }
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
        guard current > -1 else { return false }
        if isOccupiedByBuilding(x: x, y: y) { return false }
        guard s.resources.canAfford(Self.lowerCost) else { return false }
        snapshot()
        _ = s.resources.deduct(Self.lowerCost)
        s.terrain.setElev(current - 1, x: x, y: y)
        // Dropping to -1 fills with water. Higher → lower transitions
        // don't change the tile kind (a forested mountain becomes a
        // forested hill becomes a forested patch of grass).
        if current - 1 == -1 { s.terrain.setTile(.water, x: x, y: y) }
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

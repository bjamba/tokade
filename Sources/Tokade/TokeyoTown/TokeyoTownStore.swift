import Foundation
import Observation
import os.log

/// Owns the live Tokeyo Town state. Sibling of `TokenGaidenStore` — both
/// held by `TokadeApp` and fed by the same `UsageStore` event stream.
@MainActor
@Observable
final class TokeyoTownStore {
    /// The currently-active town, if any. nil → show the new-town flow.
    private(set) var state: TokeyoTownState?
    /// Latest known index (read on load; used by future multi-town UI).
    private(set) var index: TokeyoTownIndex = .empty

    /// Currently-selected tool (what tapping a tile will do).
    var tool: Tool = .hand

    enum Tool: Equatable {
        case hand                  // tap → demolish building or decor on that tile
        case build(String)         // place this building id
        case road                  // paint a road tile
        case clearTree             // remove a tree (gold cost, lumber refund)
        case plantTree             // place a tree (lumber cost)
        case levelRock             // remove a rock (industry cost)
        case plantFlower           // place a flower (growth cost)
        case lantern               // place a decoration lantern (coin cost)
    }

    /// Per-action costs / refunds. Centralized so tests + UI can read them.
    static let roadCost = TokeyoTownState.Resources(coin: 4)
    static let clearTreeCost = TokeyoTownState.Resources(coin: 8)
    static let clearTreeRefund = TokeyoTownState.Resources(lumber: 4)
    static let plantTreeCost = TokeyoTownState.Resources(lumber: 6)
    static let levelRockCost = TokeyoTownState.Resources(industry: 10)
    static let plantFlowerCost = TokeyoTownState.Resources(growth: 3)
    static let lanternCost = TokeyoTownState.Resources(coin: 12)

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
        // Seed townsfolk at spawnable tiles.
        fresh.townsfolk = TownsfolkSpawner.spawn(
            count: min(repo.contributorCount + 1, 6),
            biome: repo.biome,
            terrain: fresh.terrain,
            now: now
        )

        state = fresh

        index = TokeyoTownIndex(
            activeTownId: townId,
            towns: [
                .init(
                    townId: townId,
                    displayName: repo.displayName,
                    repoPath: repo.path,
                    biome: repo.biome,
                    lastOpenedAt: now
                ),
            ]
        )

        await save.writeTown(fresh)
        await save.writeIndex(index)
    }

    func eraseAll() async {
        await save.eraseAll()
        state = nil
        index = .empty
    }

    // MARK: - Tool selection

    func selectTool(_ tool: Tool) {
        self.tool = tool
    }

    /// Convenience for older callers that picked a building directly.
    func selectBuilding(_ kind: String?) {
        tool = kind.map { .build($0) } ?? .hand
    }

    var pendingPlacement: String? {
        if case let .build(id) = tool { return id }
        return nil
    }

    // MARK: - Placement

    /// Set of terrain kinds that buildings can sit on for this biome.
    private func allowedBuildTiles(_ biome: TokeyoTownState.Biome) -> Set<TerrainTile> {
        switch biome {
        case .beach, .desert: return [.grass, .sand]
        default: return [.grass]
        }
    }

    /// True iff the given building can be placed at (x, y) right now.
    /// Used by the renderer's placement preview *and* the actual tap.
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
        return s.resources.canAfford(b.cost)
    }

    /// Apply the current tool at tile (x, y). Returns true if something
    /// actually happened.
    @discardableResult
    func applyToolAt(x: Int, y: Int) async -> Bool {
        guard let s = state else { return false }
        switch tool {
        case .hand:
            return await handAction(state: s, x: x, y: y)
        case let .build(id):
            return await placeBuilding(id: id, x: x, y: y)
        case .road:
            return await placeRoad(x: x, y: y)
        case .clearTree:
            return await terraform(x: x, y: y, requireTile: .tree, replacement: .grass,
                                   cost: Self.clearTreeCost, refund: Self.clearTreeRefund)
        case .plantTree:
            return await terraform(x: x, y: y, requireTile: .grass, replacement: .tree,
                                   cost: Self.plantTreeCost, refund: .zero)
        case .levelRock:
            return await terraform(x: x, y: y, requireTile: .rock, replacement: .grass,
                                   cost: Self.levelRockCost, refund: .zero)
        case .plantFlower:
            return await terraform(x: x, y: y, requireTile: .grass, replacement: .flower,
                                   cost: Self.plantFlowerCost, refund: .zero)
        case .lantern:
            return await terraform(x: x, y: y, requireTile: .grass, replacement: .decor,
                                   cost: Self.lanternCost, refund: .zero)
        }
    }

    private func handAction(state s: TokeyoTownState, x: Int, y: Int) async -> Bool {
        if let hit = s.buildings.first(where: { b in
            (x >= b.tileX) && (x < b.tileX + b.width) &&
                (y >= b.tileY) && (y < b.tileY + b.height)
        }) {
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
        if tile == .flower || tile == .decor {
            var ns = s
            ns.terrain.setTile(.grass, x: x, y: y)
            state = ns
            await flush()
            return true
        }
        return false
    }

    private func placeBuilding(id: String, x: Int, y: Int) async -> Bool {
        guard canPlaceBuilding(id, at: x, y: y),
              let b = BuildingCatalog.find(id),
              var s = state else { return false }
        _ = s.resources.deduct(b.cost)
        let placed = TokeyoTownState.PlacedBuilding(
            id: UUID(),
            kind: id,
            tileX: x, tileY: y,
            width: b.shape.footprint.w,
            height: b.shape.footprint.h,
            placedAt: .now
        )
        s.buildings.append(placed)
        if isHomeBuilding(id) {
            s.townsfolk = TownsfolkSpawner.assignHomeIfNeeded(s.townsfolk, to: placed)
            if Double.random(in: 0..<1) < 0.5,
               let newcomer = TownsfolkSpawner.spawnOne(
                   biome: s.repo.biome,
                   terrain: s.terrain,
                   home: placed
               ) {
                s.townsfolk.append(newcomer)
            }
        }
        state = s
        await flush()
        return true
    }

    private func isHomeBuilding(_ id: String) -> Bool {
        ["plain-cottage", "desert-adobe", "tundra-cabin",
         "forest-treehouse", "forest-mushroom", "beach-cottage"].contains(id)
    }

    private func placeRoad(x: Int, y: Int) async -> Bool {
        guard var s = state, s.terrain.contains(x: x, y: y) else { return false }
        let current = s.terrain.tile(x: x, y: y)
        guard current == .grass || current == .sand || current == .flower else { return false }
        guard s.resources.canAfford(Self.roadCost) else { return false }
        _ = s.resources.deduct(Self.roadCost)
        s.terrain.setTile(.road, x: x, y: y)
        state = s
        await flush()
        return true
    }

    private func terraform(
        x: Int,
        y: Int,
        requireTile: TerrainTile,
        replacement: TerrainTile,
        cost: TokeyoTownState.Resources,
        refund: TokeyoTownState.Resources
    ) async -> Bool {
        guard var s = state, s.terrain.contains(x: x, y: y) else { return false }
        guard s.terrain.tile(x: x, y: y) == requireTile else { return false }
        guard s.resources.canAfford(cost) else { return false }
        _ = s.resources.deduct(cost)
        s.resources.add(refund)
        s.terrain.setTile(replacement, x: x, y: y)
        state = s
        await flush()
        return true
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

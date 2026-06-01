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

    /// How buildings label themselves in the world. Cycled by a header
    /// button. Not persisted (resets to icon each launch).
    var labelMode: LabelMode = .icon

    /// Day/night source — wall clock by default; can be forced to
    /// noon or midnight via the header toggle (useful for
    /// screenshots).
    var dayNightMode: TimeOfDay.Mode = .auto

    /// #45 — "bustle" ∈ [0, 1]: how busy the user's *current* weekday/hour
    /// usage bucket is relative to their peak bucket. Refreshed every
    /// `tick` from the live event list via `TimeOfDay.bustleFactor`. The
    /// renderer layers this on top of the wall-clock day/night light so the
    /// town's lanterns burn brighter during the hours the user actually
    /// codes. Defaults to `0` (calm) until the first tick has events.
    private(set) var bustle: Double = 0

    /// True only while the Tokeyo Town tab is on screen. The town view
    /// sets this on `.onAppear` / `.onDisappear`.
    ///
    /// ADR-0006 §7 makes the heavy simulation (townsfolk A* movement +
    /// upkeep eviction) a *foreground* responsibility — it should only run
    /// while the town is visible. Cheap resource accrual still runs every
    /// tick regardless of this flag, so the town keeps growing from your
    /// Claude usage in the background; only the expensive per-NPC pathing
    /// is gated on visibility. Defaults to `false` so a town nobody is
    /// looking at never pays the simulation cost (#54).
    var isForeground = false

    // MARK: - District ownership cache (#80 Phase 2b)

    /// Row-major district-ownership grid for the active town — the output of
    /// `DistrictGeography.ownership(...)`, computed from the current town's
    /// district seeds + per-district weights. The renderer reads this to wash
    /// each owned ground tile with its district's hue.
    ///
    /// NOT persisted and NOT observed: the BFS that produces it is O(n²) in
    /// tile count, so it must never run per render frame. It is recomputed
    /// only on adoption, when the town tab appears, and when district
    /// activity has changed since the last compute (a cheap summed-token
    /// dirty flag). `@ObservationIgnored` keeps mutating it from triggering
    /// a SwiftUI invalidation storm.
    @ObservationIgnored private(set) var districtOwnership: [Int] = []

    /// Parallel render metadata for `districtOwnership`: `districtRenderInfo[i]`
    /// describes the district that owns tiles whose ownership value is `i`.
    /// Carries just what the renderer needs (id for hue/neutral-core, name +
    /// seed for the label) so the renderer never reaches back into the store.
    @ObservationIgnored private(set) var districtRenderInfo: [DistrictRenderInfo] = []

    /// The summed `activityTokens` across all districts at the moment
    /// `districtOwnership` was last computed. Comparing the current sum to
    /// this is the cheap dirty flag that decides whether a recompute is due.
    /// `nil` means "never computed" → always recompute.
    @ObservationIgnored private var lastOwnershipActivitySum: Int?

    /// Minimal per-district info the renderer needs to tint + label tiles
    /// without depending on the store or the full `District` model.
    struct DistrictRenderInfo: Equatable {
        let id: String
        let name: String
        let seedX: Int
        let seedY: Int
    }

    /// Pure decision: should the ownership grid be recomputed?
    ///
    /// Recompute when there is no prior compute (`lastActivitySum == nil`),
    /// when forced (adoption / tab-appear), or when the districts' summed
    /// activity has changed since the last compute. Kept pure + static so the
    /// recompute-gating logic is unit-testable without a live store.
    nonisolated static func shouldRecomputeOwnership(
        currentActivitySum: Int,
        lastActivitySum: Int?,
        forced: Bool
    ) -> Bool {
        if forced { return true }
        guard let last = lastActivitySum else { return true }
        return currentActivitySum != last
    }

    /// Recompute `districtOwnership` + `districtRenderInfo` from the active
    /// town's district seeds and `DistrictGeography.weight(for:)`. No-op when
    /// there's no town. `forced` bypasses the activity dirty-flag (used on
    /// adoption and tab-appear); otherwise the grid is only rebuilt when
    /// district activity has moved since the last compute.
    ///
    /// Old saves whose districts predate seeds (Phase 2a) get their seeds
    /// backfilled here via `DistrictGeography.placeSeeds` so existing towns
    /// light up too. The backfill is in-memory only (drives this frame's
    /// render); it isn't persisted from here.
    func recomputeDistrictOwnership(forced: Bool = false) {
        guard var s = state else {
            districtOwnership = []
            districtRenderInfo = []
            lastOwnershipActivitySum = nil
            return
        }
        if s.districts == nil {
            s.districts = Districts.coreOnly(totalLOC: s.repo.loc)
        }
        var districts = s.districts ?? []
        let activitySum = districts.reduce(0) { $0 + $1.activityTokens }
        guard Self.shouldRecomputeOwnership(
            currentActivitySum: activitySum,
            lastActivitySum: lastOwnershipActivitySum,
            forced: forced
        ) else { return }

        // Backfill missing seeds (old saves) so every district has one.
        if districts.contains(where: { $0.seedX == nil || $0.seedY == nil }) {
            let placed = DistrictGeography.placeSeeds(
                districtCount: districts.count,
                mapSize: s.terrain.size,
                terrain: s.terrain,
                townId: s.townId
            )
            for (i, seed) in placed.enumerated() where i < districts.count {
                if districts[i].seedX == nil { districts[i].seedX = seed.x }
                if districts[i].seedY == nil { districts[i].seedY = seed.y }
            }
        }

        let seeds: [(x: Int, y: Int)] = districts.map { ($0.seedX ?? 0, $0.seedY ?? 0) }
        let weights = districts.map { DistrictGeography.weight(for: $0) }
        districtOwnership = DistrictGeography.ownership(
            seeds: seeds,
            weights: weights,
            mapSize: s.terrain.size,
            terrain: s.terrain
        )
        districtRenderInfo = districts.map {
            DistrictRenderInfo(
                id: $0.id, name: $0.name,
                seedX: $0.seedX ?? 0, seedY: $0.seedY ?? 0
            )
        }
        lastOwnershipActivitySum = activitySum
    }

    func cycleDayNightMode() {
        dayNightMode = dayNightMode.next
    }

    enum LabelMode: Equatable, CaseIterable {
        case icon, name, none
        var next: LabelMode {
            switch self {
            case .icon: return .name
            case .name: return .none
            case .none: return .icon
            }
        }

        var glyph: String {
            switch self {
            case .icon: return "🔠"
            case .name: return "🆎"
            case .none: return "🚫"
            }
        }

        var label: String {
            switch self {
            case .icon: return "Icons"
            case .name: return "Names"
            case .none: return "No labels"
            }
        }
    }

    func cycleLabelMode() {
        labelMode = labelMode.next
    }

    // MARK: - Resource trading

    /// Buy `1` unit of the given resource for the published coin cost.
    /// Returns true if the purchase happened.
    @discardableResult
    func buyResource(_ kind: TradeKind) async -> Bool {
        guard var s = state else { return false }
        let cost = TokeyoTownState.Resources(coin: Self.tradeCost(for: kind))
        guard s.resources.canAfford(cost) else { return false }
        snapshot()
        _ = s.resources.deduct(cost)
        switch kind {
        case .knowledge: s.resources.knowledge += 1
        case .lumber: s.resources.lumber += 1
        case .industry: s.resources.industry += 1
        case .growth: s.resources.growth += 1
        }
        state = s
        await flush()
        return true
    }

    enum TradeKind { case knowledge, lumber, industry, growth }

    /// Coin cost to buy one unit of each tradable resource. Calibrated
    /// so coin (the most abundant earned resource) is the universal
    /// purchase currency.
    static func tradeCost(for kind: TradeKind) -> Int {
        switch kind {
        case .knowledge: return 8
        case .lumber: return 8
        case .industry: return 12
        case .growth: return 15
        }
    }

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

    // `nonisolated` — these are pure value constants referenced from both the
    // @MainActor store and nonisolated pure helpers; isolating them to the main
    // actor is meaningless and trips Swift 6 isolation checking.
    nonisolated static let roadCost = TokeyoTownState.Resources(coin: 4)
    nonisolated static let clearTreeCost = TokeyoTownState.Resources(coin: 8)
    nonisolated static let clearTreeRefund = TokeyoTownState.Resources(lumber: 4)
    nonisolated static let plantTreeCost = TokeyoTownState.Resources(lumber: 6)
    nonisolated static let levelRockCost = TokeyoTownState.Resources(industry: 10)
    nonisolated static let plantFlowerCost = TokeyoTownState.Resources(growth: 3)
    nonisolated static let lanternCost = TokeyoTownState.Resources(coin: 12)
    /// Pond: paint a water tile on grass/sand. Cheap so players can use
    /// it to compose "parks" of any size + shape from water + flowers
    /// + trees + lanterns, without needing a dedicated park building.
    nonisolated static let pondCost = TokeyoTownState.Resources(coin: 10)
    // v3.2 — terrain shaping now costs coin so it's accessible from day
    // one (industry is one of the slowest-earning resources).
    nonisolated static let raiseCost = TokeyoTownState.Resources(coin: 30)
    nonisolated static let lowerCost = TokeyoTownState.Resources(coin: 30)

    // MARK: - Undo / redo

    private static let historyCap = 50
    private var undoStack: [TokeyoTownState] = []
    private var redoStack: [TokeyoTownState] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Save plumbing

    private let save: TokeyoTownSave
    private let log = Logger(subsystem: "com.bjamba.tokade", category: "TokeyoTown")
    private var dirty = false
    private var lastWriteAt: Date = .distantPast

    /// `save` is injectable so tests can point the store at a temp
    /// directory instead of `~/.tokade`. Production uses the default.
    init(save: TokeyoTownSave = TokeyoTownSave()) {
        self.save = save
    }

    func load() async {
        index = await save.readIndex()
        state = await save.readActiveTown()
        // #80 Phase 2b — prime the district-ownership grid for the loaded
        // town (forced) so districts render on the very first frame, before
        // any activity tick. No-op when there's no active town.
        recomputeDistrictOwnership(forced: true)
    }

    #if DEBUG
        /// Test-only seam: replace the live state so tests can stage exact
        /// townsfolk/resource setups (`state` is otherwise `private(set)`).
        /// Compiled out of release builds.
        func setStateForTesting(_ s: TokeyoTownState) {
            state = s
        }
    #endif

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
        // #80 Phase 1 — detect sub-packages and seed the district list
        // (top sub-packages by LOC + a synthesized "core"). Data only;
        // local-only scan, no map/geography change yet.
        let subPackages = RepoScanner.detectSubPackages(root: path)
        var districts = Districts.makeDistricts(subPackages: subPackages, totalLOC: scan.loc)
        // #80 Phase 2a — place each district's deterministic seed tile (data
        // only). Seeds are spread across buildable land, keyed off townId so
        // re-adopting the same repo yields the same layout. The full
        // ownership grid is derived (Phase 2b computes it at render time from
        // these seeds + per-district weights); we persist seeds only.
        let seeds = DistrictGeography.placeSeeds(
            districtCount: districts.count,
            mapSize: fresh.terrain.size,
            terrain: fresh.terrain,
            townId: townId
        )
        for (i, seed) in seeds.enumerated() where i < districts.count {
            districts[i].seedX = seed.x
            districts[i].seedY = seed.y
        }
        fresh.districts = districts
        undoStack.removeAll()
        redoStack.removeAll()
        state = fresh
        // #80 Phase 2b — compute the district-ownership grid for the new
        // town now (forced) so the freshly-adopted map paints its districts
        // on first render rather than waiting for the first activity tick.
        recomputeDistrictOwnership(forced: true)
        // #50 — merge the new town into the existing index rather than
        // replacing the whole `towns` list. Re-adopting an already-listed
        // repo (same townId) updates its entry in place; adopting a new
        // repo appends. Either way, previously-listed towns survive.
        let entry = TokeyoTownIndex.Entry(
            townId: townId, displayName: repo.displayName,
            repoPath: repo.path, biome: repo.biome,
            lastOpenedAt: now
        )
        var idx = index
        idx.activeTownId = townId
        if let existing = idx.towns.firstIndex(where: { $0.townId == townId }) {
            idx.towns[existing] = entry
        } else {
            idx.towns.append(entry)
        }
        index = idx
        await save.writeTown(fresh)
        await save.writeIndex(index)
    }

    /// Discard the active town and return to the new-town picker.
    ///
    /// - `archive`: keep the save file under `archive/` (default; the
    ///   v1 behaviour) so the player can come back to it later via
    ///   the index. The town no longer shows as active.
    /// - `delete`: wipe the per-town save *and* everything in the
    ///   archive — a true clean slate.
    enum ClearMode { case archive, delete }

    func clearActiveTown(mode: ClearMode) async {
        switch mode {
        case .archive:
            if let id = index.activeTownId {
                await save.archiveTown(id: id)
            }
            // Empty the index's active pointer but keep the archived
            // entry in `towns` so it could be relisted later.
            var idx = index
            idx.activeTownId = nil
            await save.writeIndex(idx)
            index = idx
        case .delete:
            // Nuke the per-town save AND any archived backups for a
            // genuine clean wipe.
            await save.eraseAll()
            index = .empty
        }
        state = nil
        undoStack.removeAll()
        redoStack.removeAll()
        // #80 Phase 2b — drop the cached ownership grid; it belongs to the
        // town we just cleared.
        recomputeDistrictOwnership(forced: true)
    }

    /// Legacy alias — old callers (and the "Erase Tokeyo Town history"
    /// menu in the app footer) still call eraseAll.
    func eraseAll() async {
        await clearActiveTown(mode: .delete)
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
        guard let (refund, restoreElevation) = Self.removalRefund(for: tile) else { return false }
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

    /// Refund (and whether to restore elevation) for removing a terrain
    /// `tile` with the hand tool. Returns `nil` for tiles the hand can't
    /// act on. Pure so it's unit-testable.
    ///
    /// #51 — water refunds NOTHING. Player-painted ponds and naturally-
    /// generated coastline water both sit at elevation -1 (see
    /// `TerrainGrid.init`), so there's no way to tell them apart;
    /// refunding the pond cost turned every beach tile into a coin
    /// printer. Refunding nothing is the smallest correct fix: never
    /// print coin for water we can't prove the player paid for. The tile
    /// is still flattened back to grass (elevation restored) by the caller.
    nonisolated static func removalRefund(
        for tile: TerrainTile
    ) -> (refund: TokeyoTownState.Resources, restoreElevation: Bool)? {
        switch tile {
        case .tree: (plantTreeCost, false)
        case .flower: (plantFlowerCost, false)
        case .decor: (lanternCost, false)
        case .road: (roadCost, false)
        case .rock: (.zero, false)
        case .water: (.zero, true)
        default: nil
        }
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
            id: UUID(), kind: id,
            tileX: x, tileY: y,
            width: b.shape.footprint.w, height: b.shape.footprint.h,
            placedAt: .now
        )
        s.buildings.append(placed)

        if isHomeBuilding(id) {
            s.townsfolk = TownsfolkSpawner.assignHomeIfNeeded(s.townsfolk, to: placed)
        }
        // v3.15 — every new building grows the population (toward a
        // cap of `buildings.count + 2`). Reads as "the town gets more
        // people as it gets denser." If the new building is a home and
        // there's room, the newcomer moves into it; otherwise they
        // wander.
        let cap = Self.populationCap(buildingCount: s.buildings.count)
        if s.townsfolk.count < cap {
            let newcomer: TokeyoTownState.Townsfolk? = if isHomeBuilding(id) {
                TownsfolkSpawner.spawnOne(
                    biome: s.repo.biome, terrain: s.terrain, home: placed
                )
            } else {
                TownsfolkSpawner.spawn(
                    count: 1, biome: s.repo.biome, terrain: s.terrain
                ).first
            }
            if let n = newcomer {
                s.townsfolk.append(n)
            }
        }

        state = s
        await flush()
        return true
    }

    /// Population the town can sustain given its building count. Caps
    /// at `buildings + 2` so a tiny hamlet of one cottage still has a
    /// couple of folks puttering around.
    static func populationCap(buildingCount: Int) -> Int {
        buildingCount + 2
    }

    /// Coin upkeep per townsfolk per AI tick. Modest enough that an
    /// actively-played game funds the town on autopilot; absentee
    /// players slowly see townsfolk leave town.
    nonisolated static let upkeepPerTownsfolkPerTick = 1

    /// #53 — upkeep eviction never drops a town below this many
    /// townsfolk. An idle, broke town shrinks toward this floor and then
    /// holds, so absenteeism can't silently empty the town. Matches the
    /// `populationCap` floor (a one-cottage hamlet keeps ~2 folks).
    nonisolated static let minPopulationFloor = 2

    /// Charge one tick of upkeep and resolve any shortfall into (at most)
    /// one eviction. Pure so it's unit-testable.
    ///
    /// #53 — the old rule evicted one townsfolk per missing coin *block*
    /// every tick (every ~3s), so an idle, broke town drained to zero
    /// within minutes. Eviction is now throttled two ways:
    ///   1. At most ONE townsfolk leaves per tick, regardless of how
    ///      large the shortfall is.
    ///   2. Eviction never drops the population below
    ///      `minPopulationFloor`, so an idle town shrinks to a small core
    ///      and then holds — it never empties.
    /// Homeless townsfolk leave before housed ones.
    nonisolated static func applyUpkeep(
        coin: Int, townsfolk: [TokeyoTownState.Townsfolk]
    ) -> (coin: Int, townsfolk: [TokeyoTownState.Townsfolk]) {
        let upkeep = townsfolk.count * upkeepPerTownsfolkPerTick
        guard upkeep > 0 else { return (coin, townsfolk) }
        let payable = min(upkeep, coin)
        let newCoin = coin - payable
        let shortfall = upkeep - payable
        guard shortfall > 0, townsfolk.count > minPopulationFloor else {
            return (newCoin, townsfolk)
        }
        var folk = townsfolk
        if let i = folk.firstIndex(where: { $0.homeBuildingId == nil }) {
            folk.remove(at: i)
        } else {
            folk.removeLast()
        }
        return (newCoin, folk)
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

    /// Resolve the active session's cwd for the 2× accrual bonus.
    ///
    /// ADR-0006 §6: the "active session cwd" is the cwd of the session the
    /// statusline reports as current — not just whichever event happened to
    /// land last. Keying off the active session id keeps the bonus from
    /// misfiring on interleaved multi-repo activity (#39). Falls back to the
    /// latest-event cwd when the active session id is unknown.
    nonisolated static func activeSessionCwd(events: [UsageEvent], activeSessionId: String?) -> String? {
        events.last(where: { $0.sessionId == activeSessionId && $0.cwd != nil })?.cwd
            ?? events.last(where: { $0.cwd != nil })?.cwd
    }

    /// Fixed coin granted once per local calendar day the player used Claude
    /// (issue #46). Small relative to ongoing accrual so it's a pleasant
    /// daily nudge, not an economy-warping windfall.
    nonisolated static let dailyStreakCoinBonus = 10

    /// Grant the once-per-local-day usage streak bonus if the player hasn't
    /// already received it today. Pure so it's unit-testable. Returns the
    /// (possibly unchanged) state.
    nonisolated static func applyStreakBonusIfNewDay(
        state: TokeyoTownState,
        events: [UsageEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TokeyoTownState {
        var s = state
        let today = calendar.startOfDay(for: now)
        if let last = s.lastStreakDay, calendar.startOfDay(for: last) == today {
            return s // already rewarded today
        }
        let streak = Streak.currentStreak(
            eventTimestamps: events.map(\.timestamp),
            now: now,
            calendar: calendar
        )
        // No live streak (e.g. no events yet today) → nothing to reward.
        guard streak >= 1 else { return s }
        s.lastStreakDay = today
        s.resources.coin += dailyStreakCoinBonus
        return s
    }

    func tick(against events: [UsageEvent], activeSessionId: String? = nil) async {
        // #45 — refresh the usage-driven "bustle" each tick so the town's
        // liveliness tracks the user's real weekday/hour coding pattern.
        // Cheap and clock-free beyond `now`; runs even if no town is active.
        bustle = TimeOfDay.bustleFactor(events: events)
        guard var s = state else { return }
        let currentCwd = Self.activeSessionCwd(events: events, activeSessionId: activeSessionId)
        let (delta, newAccounted) = ResourceAccrual.accrue(
            events: events,
            repoPath: s.repo.path,
            accounted: s.accountedEvents,
            currentSessionCwd: currentCwd
        )
        // #80 Phase 1 — attribute this tick's in-repo events to districts
        // (data only; no map change). Use the SAME high-water window the
        // accrual just consumed so district activity matches resource
        // accrual exactly. Read the prior high-water mark from the state
        // we're about to overwrite. Old saves with nil districts lazily
        // get one whole-repo "core" district (the locked migration).
        let priorHighWater = s.accountedEvents.lastTimestamp ?? .distantPast
        let tickEvents = events.filter { $0.timestamp > priorHighWater }
        if s.districts == nil {
            s.districts = Districts.coreOnly(totalLOC: s.repo.loc)
        }
        Districts.applyActivity(
            &s.districts!,
            events: tickEvents,
            repoPath: s.repo.path,
            now: .now
        )

        s.resources.add(delta)
        s.accountedEvents = newAccounted
        s.lastTickAt = .now

        // Daily usage streak bonus (issue #46): once per local calendar day
        // on which the player used Claude, drop a small fixed handful of
        // coin into the treasury. Gated on `lastStreakDay` so it fires at
        // most once per day. Kept tiny so it doesn't warp the town economy.
        s = Self.applyStreakBonusIfNewDay(state: s, events: events)

        // ADR-0006 §7 — the cheap accrual above always runs (the town
        // grows from your usage even when nobody's looking), but the
        // expensive simulation below — per-townsfolk A* pathing and upkeep
        // eviction — only runs when the tab is on screen. On a large map
        // re-planning A* for many NPCs on the main actor every 3s while
        // the view is hidden is wasted work (#54).
        if isForeground {
            // v3.15 — upkeep: every townsfolk eats 1 coin per tick. If we
            // can't fund the bill, the town slowly loses people. Pure logic
            // lives in `applyUpkeep` so it's unit-testable (#53).
            (s.resources.coin, s.townsfolk) = Self.applyUpkeep(
                coin: s.resources.coin, townsfolk: s.townsfolk
            )

            s.townsfolk = TownsfolkAI.step(
                townsfolk: s.townsfolk,
                buildings: s.buildings,
                terrain: s.terrain,
                mapSize: s.repo.mapSize
            )
        }
        state = s
        // #80 Phase 2b — refresh the district-ownership grid if this tick
        // moved district activity (the hot districts grow). Only while the
        // tab is on screen, and the internal summed-token dirty flag makes
        // it a no-op when nothing changed — so this never runs the O(n²)
        // BFS per render frame, only when geography actually shifts.
        if isForeground {
            recomputeDistrictOwnership()
        }
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

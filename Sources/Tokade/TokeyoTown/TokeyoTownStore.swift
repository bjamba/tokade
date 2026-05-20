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

    /// Pending placement chosen from the building palette. UI consumes this
    /// to know which building to drop on the next tile tap.
    var pendingPlacement: String?

    private let save = TokeyoTownSave()
    private let log = Logger(subsystem: "com.bjamba.tokade", category: "TokeyoTown")

    /// Debounce writes — at most once per 5 s. tick() sets this; place/etc.
    /// flush immediately.
    private var dirty = false
    private var lastWriteAt: Date = .distantPast

    init() {}

    func load() async {
        index = await save.readIndex()
        state = await save.readActiveTown()
    }

    // MARK: - Town lifecycle

    /// Start a new town for `path`. Replaces any existing active town
    /// (the old one is archived, not deleted — see TokeyoTownSave.archiveTown).
    func startNewTown(at path: URL, scan: RepoScanner.ScanResult, now: Date = .now) async {
        // Archive whatever active town existed.
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
        // Seed a few townsfolk so the town isn't empty on first launch.
        fresh.townsfolk = TownsfolkCatalog.spawnTownsfolk(
            count: min(repo.contributorCount + 1, 6),
            biome: repo.biome,
            mapSize: repo.mapSize,
            now: now
        )

        state = fresh

        // Rebuild the index — single-town MVP, so just one entry.
        index = TokeyoTownIndex(
            activeTownId: townId,
            towns: [
                .init(
                    townId: townId,
                    displayName: repo.displayName,
                    repoPath: repo.path,
                    biome: repo.biome,
                    lastOpenedAt: now
                )
            ]
        )

        await save.writeTown(fresh)
        await save.writeIndex(index)
    }

    /// Erase everything. Used by "Erase history…" for a clean slate.
    func eraseAll() async {
        await save.eraseAll()
        state = nil
        index = .empty
    }

    // MARK: - Game actions

    func selectBuilding(_ kind: String?) {
        pendingPlacement = kind
    }

    /// Try to place the pending building at (x, y). Returns true on success.
    @discardableResult
    func placeAt(x: Int, y: Int) async -> Bool {
        guard let kind = pendingPlacement,
              var s = state,
              let b = BuildingCatalog.find(kind),
              b.biome == s.repo.biome,
              (0..<s.repo.mapSize).contains(x),
              (0..<s.repo.mapSize).contains(y),
              !s.buildings.contains(where: { $0.tileX == x && $0.tileY == y }),
              s.resources.deduct(b.cost) else { return false }

        s.buildings.append(.init(
            id: UUID(),
            kind: kind,
            tileX: x,
            tileY: y,
            placedAt: .now
        ))
        // Each new building chance-spawns a new townsfolk so the town
        // grows organically alongside the player's work.
        if Double.random(in: 0..<1) < 0.4 {
            s.townsfolk.append(contentsOf: TownsfolkCatalog.spawnTownsfolk(
                count: 1, biome: s.repo.biome, mapSize: s.repo.mapSize
            ))
        }
        state = s
        await flush()
        return true
    }

    func demolishAt(x: Int, y: Int) async {
        guard var s = state else { return }
        s.buildings.removeAll { $0.tileX == x && $0.tileY == y }
        state = s
        await flush()
    }

    // MARK: - Tick

    /// Apply any new tokens in `events` to the town's resources. Idempotent
    /// against re-reads — high-water mark is stored on `state`.
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

        // Move townsfolk toward their goals; pick a new goal when arrived.
        s.townsfolk = s.townsfolk.map { advance($0, mapSize: s.repo.mapSize) }

        state = s
        scheduleWrite()
    }

    private func advance(
        _ npc: TokeyoTownState.Townsfolk,
        mapSize: Int
    ) -> TokeyoTownState.Townsfolk {
        var n = npc
        let dx = Double(n.goalX) - n.tileX
        let dy = Double(n.goalY) - n.tileY
        let dist = (dx * dx + dy * dy).squareRoot()
        if dist < 0.6 {
            n.tileX = Double(n.goalX)
            n.tileY = Double(n.goalY)
            n.goalX = Int.random(in: 0..<mapSize)
            n.goalY = Int.random(in: 0..<mapSize)
        } else {
            let speed: Double = 0.25
            n.tileX += dx / dist * speed
            n.tileY += dy / dist * speed
        }
        return n
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

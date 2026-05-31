@testable import Tokade
import XCTest

/// #54 — the app-wide 3s tick used to run the heavy town simulation
/// (townsfolk A* pathing + upkeep eviction) regardless of whether the
/// Tokeyo Town tab was visible, contradicting ADR-0006 §7's intent that
/// heavy foreground work only happens when the town is on screen.
///
/// These tests pin the split: a tick ALWAYS accrues resources, but only
/// moves townsfolk / runs upkeep when `isForeground == true`.
@MainActor
final class TokeyoTownCadenceTests: XCTestCase {
    private func makeScan(at url: URL) -> RepoScanner.ScanResult {
        RepoScanner.ScanResult(
            path: url,
            displayName: "repo",
            primaryLanguage: "swift",
            biome: .beach,
            era: .modern,
            ageInDays: 1,
            loc: 1000,
            contributorCount: 1,
            lushness: 0.5,
            mapSize: 16
        )
    }

    private func makeStore() -> TokeyoTownStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tokeyo-cadence-\(UUID().uuidString)")
        return TokeyoTownStore(save: TokeyoTownSave(directory: dir))
    }

    /// Townsfolk standing at (0,0) but with a goal at (5,5) — a foreground
    /// tick should path them at least one step toward the goal; a
    /// background tick should leave them exactly where they are.
    private func walker() -> TokeyoTownState.Townsfolk {
        TokeyoTownState.Townsfolk(
            id: UUID(), name: "Walker",
            tileX: 0, tileY: 0,
            homeBuildingId: nil,
            goalX: 5, goalY: 5,
            pauseRemaining: 0,
            activity: "walking",
            hue: 0.5,
            createdAt: .now
        )
    }

    /// In-repo usage events so accrual converts tokens to coin (#31 gates
    /// accrual on the adopted repo's cwd). 100k tokens → 100 coin at the
    /// 1 coin / 1,000 tokens ratio — plenty to fund upkeep, so if upkeep
    /// *did* run it still wouldn't evict; the eviction assertion below
    /// instead relies on starting from zero coin via a separate path.
    private func usageEvents(now: Date) -> [UsageEvent] {
        [UsageEvent(
            timestamp: now,
            model: "claude-opus-4-7",
            inputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            outputTokens: 100_000,
            sessionId: "s1",
            messageId: "evt-1",
            cwd: "/tmp/repo",
            tools: [],
            slashCommand: nil
        )]
    }

    /// Stage `store` with an all-grass 16×16 map (matching `mapSize`), a
    /// single cottage at the east edge, and one walker at the origin —
    /// exactly the conditions under which `TownsfolkAI.step` plans an A*
    /// path. We assert on `pathKeys` (the expensive A* output) rather than
    /// chasing multi-tick interpolation internals.
    private func stageWalkableTown(_ store: TokeyoTownStore) {
        var s = store.state!
        let size = s.repo.mapSize
        let grass = [TerrainTile](repeating: .grass, count: size * size)
        s.terrain = TerrainGrid(size: size, tiles: grass)
        s.buildings = [TokeyoTownState.PlacedBuilding(
            id: UUID(), kind: "plain-cottage",
            tileX: size - 1, tileY: 0, width: 1, height: 1,
            placedAt: .now
        )]
        s.townsfolk = [walker()]
        store.setStateForTesting(s)
    }

    func testBackgroundTickAccruesResourcesButDoesNotMoveTownsfolk() async throws {
        let store = makeStore()
        let url = URL(fileURLWithPath: "/tmp/repo")
        let createdAt = Date(timeIntervalSince1970: 1_000_000)
        await store.startNewTown(at: url, scan: makeScan(at: url), now: createdAt)
        stageWalkableTown(store)

        XCTAssertFalse(store.isForeground, "Store defaults to background (#54)")

        // Tick with events timestamped after creation so accrual fires.
        let tickAt = createdAt.addingTimeInterval(60)
        await store.tick(against: usageEvents(now: tickAt))

        let after = try XCTUnwrap(store.state)
        // Cheap accrual ran: coin went up.
        XCTAssertGreaterThan(after.resources.coin, 0,
                             "Background tick must still accrue resources (#54)")
        // Heavy A* sim did NOT run: no path was planned, nobody moved.
        XCTAssertTrue(after.townsfolk[0].pathKeys.isEmpty,
                      "Background tick must not run A* pathing (#54)")
        XCTAssertEqual(after.townsfolk[0].tileX, 0)
        XCTAssertEqual(after.townsfolk[0].tileY, 0)
    }

    /// Events that carry no tokens — accrual adds zero coin, so a town that
    /// starts broke STAYS broke and upkeep (if it runs) must evict.
    private func emptyEvents(now: Date) -> [UsageEvent] {
        [UsageEvent(
            timestamp: now,
            model: "claude-opus-4-7",
            inputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            outputTokens: 0,
            sessionId: "s1",
            messageId: "evt-empty",
            cwd: "/tmp/repo",
            tools: [],
            slashCommand: nil
        )]
    }

    func testBackgroundTickDoesNotEvictABrokeTown() async throws {
        let store = makeStore()
        let url = URL(fileURLWithPath: "/tmp/repo")
        let createdAt = Date(timeIntervalSince1970: 1_000_000)
        await store.startNewTown(at: url, scan: makeScan(at: url), now: createdAt)

        // Broke town (coin 0) with population above the floor of 2. If
        // upkeep ran it would evict one folk; in the background it must not.
        var s = try XCTUnwrap(store.state)
        s.resources = .zero
        s.townsfolk = [walker(), walker(), walker(), walker()]
        store.setStateForTesting(s)

        await store.tick(against: emptyEvents(now: createdAt.addingTimeInterval(60)))

        XCTAssertEqual(try XCTUnwrap(store.state?.townsfolk.count), 4,
                       "Background tick must not run upkeep eviction (#54)")
    }

    func testForegroundTickEvictsFromABrokeTown() async throws {
        let store = makeStore()
        let url = URL(fileURLWithPath: "/tmp/repo")
        let createdAt = Date(timeIntervalSince1970: 1_000_000)
        await store.startNewTown(at: url, scan: makeScan(at: url), now: createdAt)

        var s = try XCTUnwrap(store.state)
        s.resources = .zero
        s.townsfolk = [walker(), walker(), walker(), walker()]
        store.setStateForTesting(s)

        store.isForeground = true
        await store.tick(against: emptyEvents(now: createdAt.addingTimeInterval(60)))

        XCTAssertEqual(try XCTUnwrap(store.state?.townsfolk.count), 3,
                       "Foreground tick runs upkeep eviction on a broke town (#54)")
    }

    func testForegroundTickAccruesResourcesAndRunsTheSimulation() async throws {
        let store = makeStore()
        let url = URL(fileURLWithPath: "/tmp/repo")
        let createdAt = Date(timeIntervalSince1970: 1_000_000)
        await store.startNewTown(at: url, scan: makeScan(at: url), now: createdAt)
        stageWalkableTown(store)

        store.isForeground = true

        let tickAt = createdAt.addingTimeInterval(60)
        await store.tick(against: usageEvents(now: tickAt))

        let after = try XCTUnwrap(store.state)
        XCTAssertGreaterThan(after.resources.coin, 0,
                             "Foreground tick still accrues resources (#54)")
        // The heavy A* sim ran: the walker planned a path toward the
        // cottage (the same planning step exercised by the pathing tests).
        XCTAssertFalse(after.townsfolk[0].pathKeys.isEmpty,
                       "Foreground tick must run townsfolk A* pathing (#54)")
    }
}

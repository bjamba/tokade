@testable import Tokade
import XCTest

/// Regression tests for three Tokeyo Town economy bugs:
///   #50 — same-repo re-adoption clobbered the index's `towns` history.
///   #51 — removing natural coastline water printed coin (pond refund).
///   #53 — upkeep drained an idle town's population to zero.
@MainActor
final class TokeyoTownStoreBugsTests: XCTestCase {
    // MARK: - Helpers

    private func makeScan(at url: URL, name: String) -> RepoScanner.ScanResult {
        RepoScanner.ScanResult(
            path: url,
            displayName: name,
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

    private func makeTownsfolk(homed: Bool) -> TokeyoTownState.Townsfolk {
        TokeyoTownState.Townsfolk(
            id: UUID(), name: "T",
            tileX: 0, tileY: 0,
            homeBuildingId: homed ? UUID() : nil,
            goalX: 0, goalY: 0,
            pauseRemaining: 0,
            activity: "test",
            hue: 0.5,
            createdAt: .now
        )
    }

    // MARK: - #50: re-adoption preserves index entries

    func testReadoptingARepoPreservesOtherIndexEntries() async {
        // Point the store at a throwaway directory so we never touch the
        // real ~/.tokade saves.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tokeyo-store-bugs-\(UUID().uuidString)")
        let store = TokeyoTownStore(save: TokeyoTownSave(directory: dir))

        let urlA = URL(fileURLWithPath: "/tmp/repo-a")
        let urlB = URL(fileURLWithPath: "/tmp/repo-b")
        let idA = RepoScanner.townId(for: urlA)
        let idB = RepoScanner.townId(for: urlB)

        await store.startNewTown(at: urlA, scan: makeScan(at: urlA, name: "repo-a"))
        await store.startNewTown(at: urlB, scan: makeScan(at: urlB, name: "repo-b"))

        // Both towns are listed; B is active.
        XCTAssertEqual(Set(store.index.towns.map(\.townId)), [idA, idB])
        XCTAssertEqual(store.index.activeTownId, idB)

        // Re-adopt A. Before the #50 fix this rebuilt `towns` as a single
        // entry, dropping B entirely.
        await store.startNewTown(at: urlA, scan: makeScan(at: urlA, name: "repo-a-renamed"))

        // A is active again, AND B is still in the index (history preserved).
        XCTAssertEqual(store.index.activeTownId, idA)
        XCTAssertEqual(Set(store.index.towns.map(\.townId)), [idA, idB],
                       "Re-adopting A must not drop other listed towns (#50)")
        // A's entry was updated in place — no duplicate, and it picked up
        // the new display name.
        let aEntries = store.index.towns.filter { $0.townId == idA }
        XCTAssertEqual(aEntries.count, 1, "Re-adoption must replace A's entry in place, not duplicate it")
        XCTAssertEqual(aEntries.first?.displayName, "repo-a-renamed")
    }

    // MARK: - #51: removing natural water refunds nothing

    func testRemovingWaterRefundsNothing() {
        // Natural coastline water and player-painted ponds are
        // indistinguishable (both elev -1), so removal must refund 0 coin.
        let result = TokeyoTownStore.removalRefund(for: .water)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.refund, .zero, "Removing water must not print coin (#51)")
        XCTAssertEqual(result?.restoreElevation, true, "Water removal still flattens the tile")
    }

    func testRemovingPlacedTilesStillRefunds() {
        // Sanity: the #51 fix only zeroes water; other player-placed
        // tiles keep their refunds.
        XCTAssertEqual(TokeyoTownStore.removalRefund(for: .tree)?.refund, TokeyoTownStore.plantTreeCost)
        XCTAssertEqual(TokeyoTownStore.removalRefund(for: .flower)?.refund, TokeyoTownStore.plantFlowerCost)
        XCTAssertEqual(TokeyoTownStore.removalRefund(for: .decor)?.refund, TokeyoTownStore.lanternCost)
        XCTAssertEqual(TokeyoTownStore.removalRefund(for: .road)?.refund, TokeyoTownStore.roadCost)
        XCTAssertEqual(TokeyoTownStore.removalRefund(for: .rock)?.refund, .zero)
    }

    // MARK: - #53: upkeep doesn't zero out population on a single idle tick

    func testUpkeepDoesNotZeroPopulationOnOneIdleTick() {
        // A broke town (0 coin) with several townsfolk. Before the #53
        // fix this evicted one per missing-coin-block every tick; here a
        // single idle tick must remove at most one and never empty out.
        let folk = (0..<5).map { _ in makeTownsfolk(homed: false) }
        let (coin, after) = TokeyoTownStore.applyUpkeep(coin: 0, townsfolk: folk)

        XCTAssertEqual(coin, 0)
        XCTAssertEqual(after.count, 4, "At most one townsfolk leaves per tick when broke (#53)")
        XCTAssertGreaterThan(after.count, 0, "An idle tick must never empty the town (#53)")
    }

    func testUpkeepNeverDrainsBelowPopulationFloor() {
        // Repeatedly tick a broke town and confirm it settles at the
        // floor instead of draining to zero.
        var folk = (0..<6).map { _ in makeTownsfolk(homed: false) }
        for _ in 0..<50 {
            (_, folk) = TokeyoTownStore.applyUpkeep(coin: 0, townsfolk: folk)
        }
        XCTAssertEqual(folk.count, TokeyoTownStore.minPopulationFloor,
                       "Idle upkeep should shrink to the floor and hold, not empty (#53)")
    }

    func testUpkeepIsFreeWhenFunded() {
        // A funded town pays upkeep and loses nobody.
        let folk = (0..<4).map { _ in makeTownsfolk(homed: true) }
        let (coin, after) = TokeyoTownStore.applyUpkeep(coin: 100, townsfolk: folk)
        XCTAssertEqual(coin, 100 - folk.count * TokeyoTownStore.upkeepPerTownsfolkPerTick)
        XCTAssertEqual(after.count, folk.count)
    }
}

@testable import Tokade
import XCTest

/// Per-repo districts — Phase 3 (rescan). Issue #80.
///
/// Covers the pure merge (`Districts.mergeDistricts`) and incremental seed
/// placement (`DistrictGeography.fillMissingSeeds`) that let a rescan pick up
/// new sub-packages without losing accumulated activity or shifting existing
/// districts.
final class DistrictRescanTests: XCTestCase {
    // MARK: - Helpers

    private func sub(_ name: String, _ subpath: String, loc: Int) -> RepoScanner.SubPackageInfo {
        RepoScanner.SubPackageInfo(name: name, rootSubpath: subpath, loc: loc)
    }

    private func district(
        id: String,
        name: String? = nil,
        subpath: String,
        loc: Int,
        activity: Int = 0,
        lastActive: Date? = nil,
        seed: (Int, Int)? = nil
    ) -> TokeyoTownState.District {
        TokeyoTownState.District(
            id: id, name: name ?? id, rootSubpath: subpath, originLOC: loc,
            activityTokens: activity, lastActiveAt: lastActive,
            seedX: seed?.0, seedY: seed?.1
        )
    }

    private func grassGrid(_ size: Int) -> TerrainGrid {
        TerrainGrid(size: size, tiles: [TerrainTile](repeating: .grass, count: size * size))
    }

    // MARK: - mergeDistricts: preserve matched

    func testMergeDistrictsPreservesActivityAndSeedOnMatch() throws {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = [
            district(
                id: "packages/api", subpath: "packages/api", loc: 100,
                activity: 4200, lastActive: when, seed: (3, 7)
            ),
            district(id: "core", subpath: "", loc: 50, activity: 999, seed: (1, 1))
        ]
        // Re-detected with a refreshed (larger) LOC.
        let detected = [sub("api", "packages/api", loc: 180)]

        let merged = Districts.mergeDistricts(existing: existing, detected: detected, totalLOC: 230)

        let api = try XCTUnwrap(merged.first { $0.rootSubpath == "packages/api" })
        // Activity + seed + lastActiveAt preserved.
        XCTAssertEqual(api.activityTokens, 4200)
        XCTAssertEqual(api.lastActiveAt, when)
        XCTAssertEqual(api.seedX, 3)
        XCTAssertEqual(api.seedY, 7)
        // LOC refreshed.
        XCTAssertEqual(api.originLOC, 180)
    }

    // MARK: - mergeDistricts: new sub-package

    func testMergeDistrictsAddsNewSubPackage() throws {
        let existing = [
            district(id: "packages/api", subpath: "packages/api", loc: 100, activity: 500, seed: (2, 2)),
            district(id: "core", subpath: "", loc: 100)
        ]
        let detected = [
            sub("api", "packages/api", loc: 100),
            sub("web", "packages/web", loc: 70) // brand new
        ]

        let merged = Districts.mergeDistricts(existing: existing, detected: detected, totalLOC: 250)

        let web = try XCTUnwrap(merged.first { $0.rootSubpath == "packages/web" })
        XCTAssertEqual(web.id, "packages/web")
        XCTAssertEqual(web.originLOC, 70)
        // New district starts with no activity and no seed.
        XCTAssertEqual(web.activityTokens, 0)
        XCTAssertNil(web.lastActiveAt)
        XCTAssertNil(web.seedX)
        XCTAssertNil(web.seedY)
        // The matched api kept its seed + activity.
        let api = try XCTUnwrap(merged.first { $0.rootSubpath == "packages/api" })
        XCTAssertEqual(api.activityTokens, 500)
        XCTAssertEqual(api.seedX, 2)
    }

    // MARK: - mergeDistricts: core LOC + activity

    func testMergeDistrictsRecomputesCoreLOCAndPreservesCoreActivity() throws {
        let coreWhen = Date(timeIntervalSince1970: 1_650_000_000)
        let existing = [
            district(id: "packages/api", subpath: "packages/api", loc: 100, activity: 10, seed: (5, 5)),
            district(id: "core", subpath: "", loc: 40, activity: 7777, lastActive: coreWhen, seed: (0, 0))
        ]
        let detected = [
            sub("api", "packages/api", loc: 120),
            sub("web", "packages/web", loc: 30)
        ]

        let merged = Districts.mergeDistricts(existing: existing, detected: detected, totalLOC: 300)

        let core = try XCTUnwrap(merged.first { $0.id == "core" })
        // Core LOC = total - kept sub LOC = 300 - (120 + 30) = 150.
        XCTAssertEqual(core.originLOC, 150)
        // Core activity / lastActiveAt / seed all preserved.
        XCTAssertEqual(core.activityTokens, 7777)
        XCTAssertEqual(core.lastActiveAt, coreWhen)
        XCTAssertEqual(core.seedX, 0)
        XCTAssertEqual(core.seedY, 0)
        // Core is last.
        XCTAssertEqual(merged.last?.id, "core")
    }

    func testMergeDistrictsCoreLOCClampedAtZero() throws {
        let existing = [district(id: "core", subpath: "", loc: 0)]
        let detected = [sub("api", "packages/api", loc: 500)]
        // totalLOC smaller than the sub-package's LOC → core clamps to 0.
        let merged = Districts.mergeDistricts(existing: existing, detected: detected, totalLOC: 100)
        let core = try XCTUnwrap(merged.first { $0.id == "core" })
        XCTAssertEqual(core.originLOC, 0)
    }

    // MARK: - mergeDistricts: drop vanished

    func testMergeDistrictsDropsVanishedSubPackage() {
        let existing = [
            district(id: "packages/api", subpath: "packages/api", loc: 100, activity: 1, seed: (1, 2)),
            district(id: "packages/web", subpath: "packages/web", loc: 60, activity: 2, seed: (3, 4)),
            district(id: "core", subpath: "", loc: 40)
        ]
        // web deleted from the repo → not detected this scan.
        let detected = [sub("api", "packages/api", loc: 100)]

        let merged = Districts.mergeDistricts(existing: existing, detected: detected, totalLOC: 200)

        XCTAssertFalse(merged.contains { $0.rootSubpath == "packages/web" })
        // api + core survive.
        XCTAssertTrue(merged.contains { $0.rootSubpath == "packages/api" })
        XCTAssertTrue(merged.contains { $0.id == "core" })
        XCTAssertEqual(merged.count, 2)
    }

    func testMergeDistrictsNeverLosesCoreWhenNothingDetected() throws {
        let existing = [
            district(id: "packages/api", subpath: "packages/api", loc: 100, activity: 5),
            district(id: "core", subpath: "", loc: 50, activity: 9)
        ]
        // Repo collapsed to a single package → no sub-packages.
        let merged = Districts.mergeDistricts(existing: existing, detected: [], totalLOC: 150)
        XCTAssertEqual(merged.count, 1)
        let core = try XCTUnwrap(merged.first)
        XCTAssertEqual(core.id, "core")
        XCTAssertEqual(core.activityTokens, 9) // preserved
        XCTAssertEqual(core.originLOC, 150) // total, nothing claimed
    }

    func testMergeDistrictsSynthesizesCoreWhenAbsent() throws {
        // Defensive: existing list has NO core (shouldn't normally happen).
        let existing = [district(id: "packages/api", subpath: "packages/api", loc: 100, activity: 3)]
        let merged = Districts.mergeDistricts(existing: existing, detected: [sub("api", "packages/api", loc: 100)], totalLOC: 160)
        let core = try XCTUnwrap(merged.first { $0.id == "core" })
        XCTAssertEqual(core.originLOC, 60)
        XCTAssertEqual(core.activityTokens, 0)
    }

    func testMergeDistrictsEmptyExistingDoesNotCrash() {
        let merged = Districts.mergeDistricts(existing: [], detected: [], totalLOC: 80)
        // A core is synthesized even from nothing.
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, "core")
        XCTAssertEqual(merged.first?.originLOC, 80)
    }

    // MARK: - mergeDistricts: top-max cap

    func testMergeDistrictsRespectsTopMaxCap() {
        // Seven detected sub-packages, descending LOC; default max = 5.
        let detected = (0 ..< 7).map { i in
            sub("p\(i)", "packages/p\(i)", loc: (7 - i) * 10)
        }
        let merged = Districts.mergeDistricts(existing: [], detected: detected, totalLOC: 1000)
        // 5 sub-packages + 1 core.
        XCTAssertEqual(merged.count, 6)
        let subNames = merged.filter { !$0.rootSubpath.isEmpty }.map(\.name)
        XCTAssertEqual(subNames, ["p0", "p1", "p2", "p3", "p4"])
        XCTAssertEqual(merged.last?.id, "core")
    }

    // MARK: - fillMissingSeeds: leave existing, fill missing

    func testFillMissingSeedsLeavesExistingUntouched() {
        let grid = grassGrid(16)
        let existing: [(x: Int, y: Int)?] = [(2, 3), nil, (10, 12)]
        let filled = DistrictGeography.fillMissingSeeds(
            existingSeeds: existing, mapSize: 16, terrain: grid, townId: "t1"
        )
        XCTAssertEqual(filled.count, 3)
        // Existing seeds pass through exactly.
        XCTAssertEqual(filled[0]?.x, 2); XCTAssertEqual(filled[0]?.y, 3)
        XCTAssertEqual(filled[2]?.x, 10); XCTAssertEqual(filled[2]?.y, 12)
        // The gap is filled.
        XCTAssertNotNil(filled[1])
        // And it is distinct from the existing seeds.
        XCTAssertFalse([(2, 3), (10, 12)].contains { $0 == (filled[1]!.x, filled[1]!.y) })
    }

    func testFillMissingSeedsIsDeterministic() {
        let grid = grassGrid(16)
        let existing: [(x: Int, y: Int)?] = [(2, 3), nil, nil]
        let a = DistrictGeography.fillMissingSeeds(existingSeeds: existing, mapSize: 16, terrain: grid, townId: "town")
        let b = DistrictGeography.fillMissingSeeds(existingSeeds: existing, mapSize: 16, terrain: grid, townId: "town")
        XCTAssertEqual(a.map { $0.map { [$0.x, $0.y] } }, b.map { $0.map { [$0.x, $0.y] } })
    }

    func testFillMissingSeedsPlacesNewSeedFarFromExisting() throws {
        // One existing seed in a corner; the single new seed should land far
        // from it (the farthest-point greedy → opposite region).
        let grid = grassGrid(16)
        let existing: [(x: Int, y: Int)?] = [(0, 0), nil]
        let filled = DistrictGeography.fillMissingSeeds(
            existingSeeds: existing, mapSize: 16, terrain: grid, townId: "far"
        )
        let newSeed = try XCTUnwrap(filled[1])
        // Farthest grass tile from (0,0) on a 16×16 grid is (15,15).
        XCTAssertEqual(newSeed.x, 15)
        XCTAssertEqual(newSeed.y, 15)
    }

    func testFillMissingSeedsAllNewMatchesPlaceSeedsFirstPick() {
        // With no existing anchors, the first filled seed must match
        // placeSeeds' deterministic first pick for the same townId.
        let grid = grassGrid(12)
        let placed = DistrictGeography.placeSeeds(districtCount: 3, mapSize: 12, terrain: grid, townId: "fresh")
        let filled = DistrictGeography.fillMissingSeeds(
            existingSeeds: [nil, nil, nil], mapSize: 12, terrain: grid, townId: "fresh"
        )
        XCTAssertEqual(filled[0]?.x, placed[0].x)
        XCTAssertEqual(filled[0]?.y, placed[0].y)
    }

    func testFillMissingSeedsNoMissingIsIdentity() {
        let grid = grassGrid(8)
        let existing: [(x: Int, y: Int)?] = [(1, 1), (4, 4)]
        let filled = DistrictGeography.fillMissingSeeds(
            existingSeeds: existing, mapSize: 8, terrain: grid, townId: "x"
        )
        XCTAssertEqual(filled.map { $0.map { [$0.x, $0.y] } }, existing.map { $0.map { [$0.x, $0.y] } })
    }
}

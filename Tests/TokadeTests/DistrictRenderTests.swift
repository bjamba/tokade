@testable import Tokade
import XCTest

/// #80 Phase 2b — pure logic behind the district rendering: the
/// `districtHue` color mapping and the cache-recompute decision. The
/// rendering itself (Canvas draws) isn't unit-testable; these cover the
/// factorable pieces it depends on.
final class DistrictRenderTests: XCTestCase {
    // MARK: - districtHue determinism

    func testDistrictHueIsDeterministicForSameId() {
        let a = DistrictGeography.districtHue(id: "packages/api")
        let b = DistrictGeography.districtHue(id: "packages/api")
        XCTAssertEqual(a, b, "same id must always map to the same hue")
    }

    func testDistrictHueCoreIsNeutralSentinel() {
        // The synthesized core district renders neutral (no tint): the
        // helper returns the -1 sentinel rather than a hue in [0, 1).
        XCTAssertEqual(DistrictGeography.districtHue(id: Districts.coreId), -1)
    }

    func testDistrictHueNonCoreIsInUnitRange() {
        for id in ["packages/api", "packages/web", "services/worker", "src", "app"] {
            let h = DistrictGeography.districtHue(id: id)
            XCTAssertGreaterThanOrEqual(h, 0, "\(id) hue must be >= 0")
            XCTAssertLessThan(h, 1, "\(id) hue must be < 1")
        }
    }

    // MARK: - districtHue spread

    func testDistinctIdsGetDistinctHues() {
        let ids = [
            "packages/api", "packages/web", "packages/app",
            "services/worker", "services/cron",
            "src", "app", "lib", "core-pkg", "tools",
        ]
        let hues = ids.map { DistrictGeography.districtHue(id: $0) }
        let unique = Set(hues.map { ($0 * 1_000_000).rounded() })
        XCTAssertEqual(unique.count, ids.count,
                       "distinct ids must map to distinct hues")
    }

    func testNearIdenticalIdsAreWellSeparated() {
        // Near-identical ids (one char apart) must not collapse onto
        // visually-indistinguishable hues — the golden-ratio scatter should
        // push them apart on the wheel.
        let a = DistrictGeography.districtHue(id: "packages/api")
        let b = DistrictGeography.districtHue(id: "packages/app")
        // Circular distance on the hue wheel.
        let raw = abs(a - b)
        let circular = min(raw, 1 - raw)
        XCTAssertGreaterThan(circular, 0.02,
                             "near-identical ids should be separated on the hue wheel")
    }

    // MARK: - Recompute decision logic

    func testShouldRecomputeWhenNeverComputed() {
        XCTAssertTrue(TokeyoTownStore.shouldRecomputeOwnership(
            currentActivitySum: 0, lastActivitySum: nil, forced: false
        ))
    }

    func testShouldRecomputeWhenForced() {
        XCTAssertTrue(TokeyoTownStore.shouldRecomputeOwnership(
            currentActivitySum: 100, lastActivitySum: 100, forced: true
        ))
    }

    func testShouldNotRecomputeWhenActivityUnchanged() {
        XCTAssertFalse(TokeyoTownStore.shouldRecomputeOwnership(
            currentActivitySum: 420, lastActivitySum: 420, forced: false
        ))
    }

    func testShouldRecomputeWhenActivityChanged() {
        XCTAssertTrue(TokeyoTownStore.shouldRecomputeOwnership(
            currentActivitySum: 421, lastActivitySum: 420, forced: false
        ))
    }
}

@testable import Tokade
import XCTest

/// Coverage for the region-boss helpers (issue #42): picking the most-used
/// project and mapping each stack flavor to a real gear drop.
final class RegionBossTests: XCTestCase {
    private func freshState() -> TokegotchiState {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        return TokegotchiState.newStarter(name: "Boba", appearance: appearance)
    }

    func testMostUsedRegionPicksTheMaximum() {
        var state = freshState()
        state.world.eventCounts = [
            "code/quiet": 3,
            "code/busy": 42,
            "code/middling": 17,
        ]
        XCTAssertEqual(Region.mostUsedRegion(state: state), "code/busy")
    }

    func testMostUsedRegionIsNilWhenEmpty() {
        var state = freshState()
        // No eventCounts at all (legacy/M0 schema).
        state.world.eventCounts = nil
        XCTAssertNil(Region.mostUsedRegion(state: state))
        // Present but empty.
        state.world.eventCounts = [:]
        XCTAssertNil(Region.mostUsedRegion(state: state))
    }

    func testMostUsedRegionTieBreakIsDeterministic() {
        var state = freshState()
        state.world.eventCounts = ["alpha": 10, "beta": 10]
        // A tie must resolve to a single stable region regardless of dict order.
        let first = Region.mostUsedRegion(state: state)
        XCTAssertNotNil(first)
        for _ in 0..<20 {
            XCTAssertEqual(Region.mostUsedRegion(state: state), first)
        }
    }

    func testThemedGearMapsEveryFlavorToARealCatalogItem() {
        for flavor in Region.Flavor.allCases {
            guard let id = Region.themedGear(forFlavor: flavor) else {
                XCTFail("No themed gear for flavor \(flavor)")
                continue
            }
            XCTAssertNotNil(
                GearCatalog.find(id),
                "themedGear(forFlavor: \(flavor)) returned unknown gear id \(id)"
            )
        }
    }
}

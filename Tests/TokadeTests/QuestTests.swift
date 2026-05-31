@testable import Tokade
import XCTest

final class QuestTests: XCTestCase {
    private func freshState() -> TokegotchiState {
        let app = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        return TokegotchiState.newStarter(name: "Boba", appearance: app)
    }

    func testAcceptThenEvaluateBashQuest() throws {
        var s = freshState()
        // Real catalog quest: "stone-50-bash" — Bash 50 times.
        let q = try XCTUnwrap(QuestCatalog.byId("stone-50-bash"))
        let (accepted, accResult) = QuestEngine.accept(q, state: s)
        XCTAssertEqual(accResult, .accepted)
        XCTAssertEqual(QuestEngine.active(state: accepted).count, 1)
        s = accepted

        var telemetry = QuestTelemetry()
        telemetry.toolCounts["Bash"] = 30
        s = QuestEngine.evaluate(state: s, telemetry: telemetry)
        XCTAssertEqual(QuestEngine.active(state: s).first?.progress, 30)
        XCTAssertEqual(QuestEngine.active(state: s).first?.completed, false)

        telemetry.toolCounts["Bash"] = 50
        s = QuestEngine.evaluate(state: s, telemetry: telemetry)
        XCTAssertEqual(QuestEngine.active(state: s).first?.completed, true)
    }

    func testClaimPaysReward() throws {
        var s = freshState()
        let q = try XCTUnwrap(QuestCatalog.byId("garden-wise"))   // reach INT 8
        let (accepted, _) = QuestEngine.accept(q, state: s)
        s = accepted
        s.vitals.stats.int = 8
        s = QuestEngine.evaluate(state: s, telemetry: QuestTelemetry())
        XCTAssertEqual(QuestEngine.active(state: s).first?.completed, true)
        let goldBefore = s.progress.gold
        let expBefore  = s.progress.exp
        let (after, claim) = QuestEngine.claim(q, state: s)
        XCTAssertEqual(claim, .claimed(gold: q.rewardGold, exp: q.rewardExp, item: q.rewardItem))
        XCTAssertEqual(after.progress.gold, goldBefore + q.rewardGold)
        XCTAssertEqual(after.progress.exp,  expBefore  + q.rewardExp)
        XCTAssertEqual(QuestEngine.active(state: after).count, 0)
    }

    /// Regression for #56: the "Wanderer's Way" quest ("visit 3 distinct
    /// regions") must count distinct regions, not reputation in any one
    /// region. Distinct regions are the keys of `world.eventCounts`.
    func testVisitRegionsTracksDistinctRegionCount() throws {
        var s = freshState()
        let q = try XCTUnwrap(QuestCatalog.byId("steppe-explore"))
        if case let .visitRegions(count) = q.objective {
            XCTAssertEqual(count, 3)
        } else {
            XCTFail("steppe-explore should use .visitRegions, got \(q.objective)")
        }
        let (accepted, _) = QuestEngine.accept(q, state: s)
        s = accepted

        // Two distinct regions visited: not done, progress capped at 2.
        s.world.eventCounts = ["projA": 5, "projB": 1]
        s = QuestEngine.evaluate(state: s, telemetry: QuestTelemetry())
        XCTAssertEqual(QuestEngine.active(state: s).first?.progress, 2)
        XCTAssertEqual(QuestEngine.active(state: s).first?.completed, false)

        // A third distinct region tips it over the line.
        s.world.eventCounts = ["projA": 5, "projB": 1, "projC": 9]
        s = QuestEngine.evaluate(state: s, telemetry: QuestTelemetry())
        XCTAssertEqual(QuestEngine.active(state: s).first?.progress, 3)
        XCTAssertEqual(QuestEngine.active(state: s).first?.completed, true)
    }

    func testHaggleDiscountCappedAt24() {
        XCTAssertEqual(NPCInteraction.haggleDiscount(cha: 0), 0)
        XCTAssertEqual(NPCInteraction.haggleDiscount(cha: 10), 0.10)
        XCTAssertEqual(NPCInteraction.haggleDiscount(cha: 100), 0.24)
    }

    func testHaggledPriceFloorsAtOne() {
        let offer = ShopOffer(itemId: "bread", priceGold: 3)
        XCTAssertGreaterThanOrEqual(NPCInteraction.haggledPrice(offer, cha: 100), 1)
    }
}

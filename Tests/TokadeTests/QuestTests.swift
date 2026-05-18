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

    func testAcceptThenEvaluateBashQuest() {
        var s = freshState()
        // Real catalog quest: "stone-50-bash" — Bash 50 times.
        let q = QuestCatalog.byId("stone-50-bash")!
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

    func testClaimPaysReward() {
        var s = freshState()
        let q = QuestCatalog.byId("garden-wise")!   // reach INT 8
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

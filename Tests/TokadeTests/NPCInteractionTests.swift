@testable import Tokade
import XCTest

final class NPCInteractionTests: XCTestCase {
    private func freshState() -> TokegotchiState {
        let app = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        return TokegotchiState.newStarter(name: "Boba", appearance: app)
    }

    func testBuySucceedsWhenGoldSufficient() {
        var s = freshState()
        s.progress.gold = 100
        let offer = ShopOffer(itemId: "bread", priceGold: 5)
        let (after, result) = NPCInteraction.buy(offer, state: s)
        XCTAssertEqual(after.progress.gold, 95)
        XCTAssertEqual(after.inventory.items["bread"], (s.inventory.items["bread"] ?? 0) + 1)
        XCTAssertEqual(result, .bought(itemId: "bread", price: 5))
    }

    func testBuyFailsWithInsufficientGold() {
        var s = freshState()
        s.progress.gold = 2
        let offer = ShopOffer(itemId: "feast", priceGold: 60)
        let (after, result) = NPCInteraction.buy(offer, state: s)
        XCTAssertEqual(after, s)
        XCTAssertEqual(result, .insufficientGold)
    }

    func testTrainSucceedsWhenExpSufficient() {
        var s = freshState()
        s.progress.exp = 50
        let offering = TrainerOffering(id: "str-1", label: "+1 STR", priceExp: 25, effect: .statBoost(stat: "STR", delta: 1))
        let (after, result) = NPCInteraction.train(offering, state: s)
        XCTAssertEqual(after.progress.exp, 25)
        XCTAssertEqual(after.vitals.stats.str, s.vitals.stats.str + 1)
        XCTAssertEqual(result, .trained(label: "+1 STR", costExp: 25))
    }

    func testTrainFailsWithInsufficientExp() {
        var s = freshState()
        s.progress.exp = 5
        let offering = TrainerOffering(id: "str-1", label: "+1 STR", priceExp: 25, effect: .statBoost(stat: "STR", delta: 1))
        let (after, result) = NPCInteraction.train(offering, state: s)
        XCTAssertEqual(after, s)
        XCTAssertEqual(result, .insufficientExp)
    }

    func testRosterHasMerchantAndTrainerForKnownFlavors() {
        for flavor in [Region.Flavor.stonework, .ironFortress, .gardenVillage, .bazaar, .openSteppe] {
            let npcs = NPCRoster.npcs(for: flavor)
            XCTAssertGreaterThanOrEqual(npcs.count, 2, "\(flavor) missing NPCs")
            XCTAssertTrue(npcs.contains { if case .merchant = $0.role { return true } else { return false } })
            XCTAssertTrue(npcs.contains { if case .trainer = $0.role { return true } else { return false } })
        }
    }
}

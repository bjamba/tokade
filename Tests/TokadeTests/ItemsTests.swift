@testable import Tokade
import XCTest

final class ItemsTests: XCTestCase {
    private func freshState() -> TokegotchiState {
        let app = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        return TokegotchiState.newStarter(name: "Boba", appearance: app)
    }

    func testFoodHealsWithClamp() {
        var s = freshState()
        s.vitals.hp = 50
        s.inventory.items["hearty-meat"] = 2
        let (next, result) = ItemUsage.use("hearty-meat", state: s)
        XCTAssertEqual(next.vitals.hp, 75)
        XCTAssertEqual(next.inventory.items["hearty-meat"], 1)
        if case let .healed(hp) = result { XCTAssertEqual(hp, 25) } else { XCTFail() }
    }

    func testFoodCantOverhealOverMax() {
        var s = freshState()
        s.vitals.hp = s.vitals.hpMax - 2
        s.inventory.items["feast"] = 1
        let (next, _) = ItemUsage.use("feast", state: s)
        XCTAssertEqual(next.vitals.hp, next.vitals.hpMax)
    }

    func testMissingItemReturnsMissing() {
        let s = freshState()
        let (next, result) = ItemUsage.use("hearty-meat", state: s)
        XCTAssertEqual(next, s)
        XCTAssertEqual(result, .missing)
    }

    func testStatBoostItem() {
        var s = freshState()
        s.inventory.items["dumbbell"] = 3
        let (next, _) = ItemUsage.use("dumbbell", state: s)
        XCTAssertEqual(next.vitals.stats.str, s.vitals.stats.str + 1)
        XCTAssertEqual(next.inventory.items["dumbbell"], 2)
    }

    func testScrapSellsForGold() {
        var s = freshState()
        s.inventory.items["scrap"] = 5
        let (next, result) = ItemUsage.use("scrap", state: s)
        XCTAssertEqual(next.progress.gold, 2)
        XCTAssertEqual(next.inventory.items["scrap"], 4)
        XCTAssertEqual(result, .sold(gold: 2))
    }
}

final class AchievementTests: XCTestCase {
    private func freshState() -> TokegotchiState {
        let app = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        return TokegotchiState.newStarter(name: "Boba", appearance: app)
    }

    func testFirstLightFiresImmediately() {
        let earned = AchievementCatalog.newlyEarned(in: freshState())
        XCTAssertTrue(earned.contains("first-light"))
    }

    func testStrengthMilestone() {
        var s = freshState()
        s.vitals.stats.str = 10
        XCTAssertTrue(AchievementCatalog.newlyEarned(in: s).contains("strong-start"))
    }

    func testAlreadyEarnedDoesntRefire() {
        var s = freshState()
        s.inventory.items["achievement:first-light"] = 1
        XCTAssertFalse(AchievementCatalog.newlyEarned(in: s).contains("first-light"))
    }
}

final class EncounterTests: XCTestCase {
    func testVictoryPaysExpAndGold() {
        let app = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        var s = TokegotchiState.newStarter(name: "Boba", appearance: app)
        s.vitals.stats.str = 20
        s.vitals.stats.dex = 20
        let m = Encounter(monsterName: "Slime", hp: 10, attack: 1, defense: 0, expReward: 5, goldReward: 3)
        let (after, outcome) = EncounterEngine.resolve(m, against: s)
        XCTAssertEqual(after.progress.exp, 5)
        XCTAssertEqual(after.progress.gold, 3)
        XCTAssertEqual(outcome, .victory(expGained: 5, goldGained: 3))
    }

    func testFleeWhenOutmatched() {
        let app = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        let s = TokegotchiState.newStarter(name: "Boba", appearance: app)
        let bigMonster = Encounter(monsterName: "Worldeater", hp: 1000, attack: 20, defense: 99, expReward: 9999, goldReward: 9999)
        let (after, outcome) = EncounterEngine.resolve(bigMonster, against: s)
        XCTAssertEqual(after.progress.exp, 0)
        XCTAssertEqual(after.progress.gold, 0)
        XCTAssertEqual(outcome, .fled)
    }

    func testChoosePicksBeatableMonster() {
        let stats = TokegotchiState.Stats(str: 50, dex: 50, int: 5, agi: 5, cha: 5)
        let m = EncounterEngine.choose(for: .ironFortress, playerStats: stats, salt: 0)
        XCTAssertNotNil(m)
    }
}

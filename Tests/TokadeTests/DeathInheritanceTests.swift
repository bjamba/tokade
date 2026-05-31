@testable import Tokade
import XCTest

@MainActor
final class DeathInheritanceTests: XCTestCase {
    private func appearance() -> TokegotchiState.Appearance {
        TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
    }

    func testCriticalGraceElapsesThenDies() {
        var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance())
        state.vitals.hp = 0
        let t0 = Date()
        // First clock tick enters critical and stamps the time.
        let (s, _) = TickProcessor.advanceCriticalClock(state: state, now: t0)
        XCTAssertEqual(s.criticalSince, t0)
        XCTAssertFalse(s.isDead)

        // Once the grace seconds elapse by wall clock, the pet dies — no Claude
        // usage required (issue #37).
        let (dead, _) = TickProcessor.advanceCriticalClock(
            state: s, now: t0.addingTimeInterval(TokegotchiState.criticalGraceSeconds)
        )
        XCTAssertTrue(dead.isDead)
        XCTAssertEqual(dead.deathState?.cause, .hpZero)
    }

    func testHealingCancelsCritical() {
        var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance())
        state.vitals.hp = 0
        let t0 = Date()
        var (s, _) = TickProcessor.advanceCriticalClock(state: state, now: t0)
        XCTAssertNotNil(s.criticalSince)
        // Heal manually, then the next clock tick clears the stamp.
        s.vitals.hp = 50
        let (next, _) = TickProcessor.advanceCriticalClock(state: s, now: t0.addingTimeInterval(10))
        XCTAssertNil(next.criticalSince)
        XCTAssertFalse(next.isDead)
    }

    func testNaturalDeathFromAgeOut() {
        var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance())
        state.identity.lifespanTokens = 100
        state.identity.ageTokens = 100   // already at the cap
        let event = UsageEvent(
            timestamp: Date(),
            model: "claude-sonnet-4-6",
            inputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0, outputTokens: 1,
            sessionId: "s", messageId: "m", cwd: nil, tools: [], slashCommand: nil
        )
        let (after, _) = TickProcessor.process(event, state: state, deltaTokens: 1)
        XCTAssertTrue(after.isDead)
        XCTAssertEqual(after.deathState?.cause, .natural)
    }

    func testFeedingClearsCriticalAtomically() async throws {
        // Issue #38: feeding a critical pet must clear `criticalSince` in the
        // same step as the heal, not on the next store tick. Otherwise an
        // event that re-drops HP to 0 before that tick resumes a stale stamp
        // near the death threshold.
        let g = TokenGaidenStore(notifier: nil)
        await g.startNewLineage(name: "Boba", appearance: appearance())
        var pet = try XCTUnwrap(g.state)
        pet.vitals.hp = 0
        pet.criticalSince = Date()
        pet.inventory.items = ["hearty-meat": 1]
        g.setStateForTesting(pet)

        await g.useItem("hearty-meat")

        let after = try XCTUnwrap(g.state)
        XCTAssertGreaterThan(after.vitals.hp, 0)
        XCTAssertNil(after.criticalSince)
        await g.eraseHistory()
    }

    func testInheritanceCarriesThirtyPercentAndItems() async throws {
        let g = TokenGaidenStore(notifier: nil)
        await g.startNewLineage(name: "Boba", appearance: appearance())
        // Stage a "dead" predecessor with substantial state.
        var pet = try XCTUnwrap(g.state)
        pet.vitals.stats = TokegotchiState.Stats(str: 20, dex: 10, int: 30, agi: 40, cha: 50)
        pet.progress.gold = 1000
        pet.inventory.items = ["bread": 5, "scroll": 2]
        pet.inventory.equippedCosmetic = ["hair": "spiky", "shirt": "tunic", "pants": "long-pants", "belt": "leather", "hat": nil, "eyewear": nil, "cape": nil]
        pet.world.reputation = ["code/a": 30, "code/b": 12]
        pet.deathState = TokegotchiState.PendingDeath(
            cause: .natural,
            diedAt: Date(),
            peakStats: pet.vitals.stats,
            daysLived: 6
        )
        // Stuff it directly into the store, then hatch next.
        g.setStateForTesting(pet)
        await g.hatchNextGeneration(name: "Boba II", appearance: appearance())
        let fresh = try XCTUnwrap(g.state)
        XCTAssertEqual(fresh.identity.generation, 2)
        // Inheritance is now baseline + ceil(peak/4). Baseline is random in
        // [3, 10] so we check the bonus magnitude rather than an exact match.
        // STR peak 20 → +5 bonus; CHA peak 50 → +13 bonus.
        XCTAssertGreaterThanOrEqual(fresh.vitals.stats.str, 3 + 5)
        XCTAssertLessThanOrEqual(fresh.vitals.stats.str, 10 + 5)
        XCTAssertGreaterThanOrEqual(fresh.vitals.stats.cha, 3 + 13)
        XCTAssertLessThanOrEqual(fresh.vitals.stats.cha, 10 + 13)
        XCTAssertEqual(fresh.progress.gold, 100)     // 10% of 1000
        XCTAssertEqual(fresh.inventory.items["bread"], 5)
        XCTAssertEqual(fresh.world.reputation["code/a"], 30)
        XCTAssertEqual(fresh.bloodline.ancestors.count, 1)
        XCTAssertEqual(fresh.bloodline.ancestors.first?.daysLived, 6)
        await g.eraseHistory()
    }
}

@testable import Tokade
import XCTest

final class TickProcessorTests: XCTestCase {
    private func event(model: String, tokens: Int, messageId: String) -> UsageEvent {
        UsageEvent(
            timestamp: Date(), model: model,
            inputTokens: tokens, cacheCreationTokens: 0, cacheReadTokens: 0, outputTokens: 0,
            sessionId: "s", messageId: messageId, cwd: nil, tools: [], slashCommand: nil
        )
    }

    func testModelSeverityIsSonnetCentered() {
        // Sonnet stays at 1.0 so the plan-normalized calibration is unchanged;
        // Haiku gentler, Opus harsher; unknown models neutral (issue #36).
        XCTAssertEqual(TickProcessor.modelSeverity(model: "claude-haiku-4-5"), 0.5)
        XCTAssertEqual(TickProcessor.modelSeverity(model: "claude-sonnet-4-6"), 1.0)
        XCTAssertEqual(TickProcessor.modelSeverity(model: "claude-opus-4-7"), 2.0)
        XCTAssertEqual(TickProcessor.modelSeverity(model: "future-model"), 1.0)
    }

    func testModelMixIsTokenWeightedWithDominantLabel() {
        // 90k Opus + 10k Haiku → weighted mean = (90k*2 + 10k*0.5)/100k = 1.85,
        // and Opus is > 60% of tokens so it's the label.
        let mix = TickProcessor.modelMix(for: [
            event(model: "claude-opus-4-7", tokens: 90000, messageId: "a"),
            event(model: "claude-haiku-4-5", tokens: 10000, messageId: "b"),
        ])
        XCTAssertEqual(mix.multiplier, 1.85, accuracy: 0.0001)
        XCTAssertEqual(mix.label, "Opus")

        // Even split → "mixed", multiplier the mean of the two severities.
        let even = TickProcessor.modelMix(for: [
            event(model: "claude-opus-4-7", tokens: 50000, messageId: "c"),
            event(model: "claude-haiku-4-5", tokens: 50000, messageId: "d"),
        ])
        XCTAssertEqual(even.multiplier, 1.25, accuracy: 0.0001)
        XCTAssertEqual(even.label, "mixed")

        // No billable tokens → neutral.
        XCTAssertEqual(TickProcessor.modelMix(for: []), .neutral)
    }

    func testApplyBudgetWearScalesAgingByModelMix() {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        func wearOnce(mix: TickProcessor.ModelMix) -> (hp: Int, age: Int) {
            var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance)
            state.vitals.hp = state.vitals.hpMax
            let (s1, _) = TickProcessor.applyBudgetWear(state: state, usedPercentage: 0, modelMix: mix)
            let (s2, _) = TickProcessor.applyBudgetWear(state: s1, usedPercentage: 50, modelMix: mix)
            return (state.vitals.hpMax - s2.vitals.hp, s2.identity.ageTokens)
        }
        let haiku = wearOnce(mix: TickProcessor.ModelMix(multiplier: 0.5, label: "Haiku"))
        let sonnet = wearOnce(mix: .neutral)
        let opus = wearOnce(mix: TickProcessor.ModelMix(multiplier: 2.0, label: "Opus"))

        // Aging takes the full multiplier: Opus ages ~2× Sonnet, Haiku ~0.5×.
        XCTAssertEqual(sonnet.age, 750_000)        // 0.5 window * 1.5M
        XCTAssertEqual(opus.age, 1_500_000)        // ×2.0
        XCTAssertEqual(haiku.age, 375_000)         // ×0.5
        // HP takes the softened (half-strength) multiplier, so Opus drains
        // more than Sonnet but not double.
        XCTAssertGreaterThan(opus.hp, sonnet.hp)
        XCTAssertLessThan(haiku.hp, sonnet.hp)
        XCTAssertLessThan(opus.hp, sonnet.hp * 2)
    }

    func testToolDropMapping() {
        XCTAssertEqual(TickProcessor.toolDrop(tool: "Bash").itemId, "dumbbell")
        XCTAssertEqual(TickProcessor.toolDrop(tool: "Edit").itemId, "chisel")
        XCTAssertEqual(TickProcessor.toolDrop(tool: "Write").itemId, "chisel")
        XCTAssertEqual(TickProcessor.toolDrop(tool: "WebFetch").itemId, "scroll")
        XCTAssertEqual(TickProcessor.toolDrop(tool: "WebSearch").itemId, "scroll")
        XCTAssertEqual(TickProcessor.toolDrop(tool: "Task").itemId, "boots")
        XCTAssertEqual(TickProcessor.toolDrop(tool: "Read").itemId, "scrap")
        XCTAssertEqual(TickProcessor.toolDrop(tool: "Grep").itemId, "scrap")
        XCTAssertEqual(TickProcessor.toolDrop(tool: "ExitPlanMode").itemId, "scrap")
        // MCP namespaced tools default to scrap.
        XCTAssertEqual(TickProcessor.toolDrop(tool: "mcp__github__create_issue").itemId, "scrap")
    }

    func testApplyBudgetWearDrainsHPAndAgesByPercentage() {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance)
        state.vitals.hp = state.vitals.hpMax
        // First observation: only baselines, no wear.
        let (s1, r1) = TickProcessor.applyBudgetWear(state: state, usedPercentage: 0)
        XCTAssertEqual(s1.identity.lastUsedPercentage, 0)
        XCTAssertEqual(s1.vitals.hp, state.vitals.hpMax)
        XCTAssertEqual(r1.count, 0)
        // 50% jump → half a window's worth of wear. With current constants:
        // 60 HP * 0.5 = 30, ageTokensPerFullWindow * 0.5 = 750_000.
        let (s2, r2) = TickProcessor.applyBudgetWear(state: s1, usedPercentage: 50)
        XCTAssertEqual(s2.vitals.hp, state.vitals.hpMax - 30)
        XCTAssertEqual(s2.identity.ageTokens, 750_000)
        XCTAssertTrue(r2.contains(.hpChanged(delta: -30)))
        XCTAssertEqual(s2.identity.lastUsedPercentage, 50)
        // Window rollover (pct decreases) is treated as no wear.
        let (s3, r3) = TickProcessor.applyBudgetWear(state: s2, usedPercentage: 10)
        XCTAssertEqual(s3.vitals.hp, s2.vitals.hp)
        XCTAssertEqual(s3.identity.ageTokens, s2.identity.ageTokens)
        XCTAssertEqual(r3.count, 0)
    }

    func testToolDropsRequireThreshold() {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance)
        // First Bash call shouldn't drop anything (threshold is 5).
        let event = UsageEvent(
            timestamp: Date(),
            model: "claude-sonnet-4-6",
            inputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0, outputTokens: 1,
            sessionId: "s1", messageId: "m1", cwd: nil, tools: ["Bash"], slashCommand: nil
        )
        for i in 1...TickProcessor.toolDropThreshold {
            let e = UsageEvent(
                timestamp: event.timestamp,
                model: event.model,
                inputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0, outputTokens: 1,
                sessionId: "s1", messageId: "m\(i)",
                cwd: nil, tools: ["Bash"], slashCommand: nil
            )
            let (next, _) = TickProcessor.process(e, state: state, deltaTokens: 1)
            state = next
        }
        XCTAssertEqual(state.inventory.items["dumbbell"], 1)
    }

    func testCriticalClockEntersOncePersistsWhileIdleAndDiesAfterGrace() {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance)
        state.vitals.hp = 0
        let t0 = Date()

        // First clock tick at HP=0 enters Critical and stamps the time.
        let (s1, r1) = TickProcessor.advanceCriticalClock(state: state, now: t0)
        XCTAssertEqual(s1.criticalSince, t0)
        XCTAssertTrue(r1.contains(.enteredCritical))

        // An idle tick partway through the grace window: still critical, no
        // re-entry, not dead — even though no Claude usage happened.
        let (s2, r2) = TickProcessor.advanceCriticalClock(
            state: s1, now: t0.addingTimeInterval(TokegotchiState.criticalGraceSeconds - 1)
        )
        XCTAssertFalse(r2.contains(.enteredCritical))
        XCTAssertFalse(s2.isDead)

        // Once the grace seconds elapse — purely by wall clock — the pet dies.
        let (s3, r3) = TickProcessor.advanceCriticalClock(
            state: s2, now: t0.addingTimeInterval(TokegotchiState.criticalGraceSeconds)
        )
        XCTAssertTrue(r3.contains(.died(cause: .hpZero)))
        XCTAssertTrue(s3.isDead)
    }

    func testCriticalClockRecoversWhenHPRestored() {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance)
        state.vitals.hp = 0
        let t0 = Date()
        let (down, _) = TickProcessor.advanceCriticalClock(state: state, now: t0)
        XCTAssertNotNil(down.criticalSince)

        // Pet is fed back above zero, then the next clock tick clears the stamp
        // and does not kill it even past the original grace window.
        var fed = down
        fed.vitals.hp = 20
        let (recovered, _) = TickProcessor.advanceCriticalClock(
            state: fed, now: t0.addingTimeInterval(TokegotchiState.criticalGraceSeconds + 10)
        )
        XCTAssertNil(recovered.criticalSince)
        XCTAssertFalse(recovered.isDead)
    }

    func testProcessFiresDiedOnAgeOut() {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance)
        state.identity.lifespanTokens = 100
        state.identity.ageTokens = 100   // already at the cap
        // A no-op event tick should detect the aged-out condition.
        let event = UsageEvent(
            timestamp: Date(),
            model: "claude-sonnet-4-6",
            inputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0, outputTokens: 100,
            sessionId: "s1", messageId: "m1", cwd: nil, tools: [], slashCommand: nil
        )
        let (after, results) = TickProcessor.process(event, state: state, deltaTokens: 100)
        XCTAssertTrue(after.isAgedOut)
        XCTAssertTrue(results.contains(.died(cause: .natural)))
    }
}

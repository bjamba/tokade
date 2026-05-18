@testable import Tokade
import XCTest

final class TickProcessorTests: XCTestCase {
    func testHpDrainRates() {
        // Calibrated for real Claude usage — see TickProcessor.hpDrain.
        XCTAssertEqual(TickProcessor.hpDrain(model: "claude-haiku-4-5",  tokens: 1_000_000), 5)
        XCTAssertEqual(TickProcessor.hpDrain(model: "claude-sonnet-4-6", tokens: 1_000_000), 10)
        XCTAssertEqual(TickProcessor.hpDrain(model: "claude-opus-4-7",   tokens: 1_000_000), 25)
        // Unknown models fall back to a moderate rate.
        XCTAssertEqual(TickProcessor.hpDrain(model: "future-model", tokens: 1_600_000), 10)
    }

    func testAgeMultipliers() {
        XCTAssertEqual(TickProcessor.ageAdvance(model: "claude-haiku-4-5", tokens: 1000), 500)
        XCTAssertEqual(TickProcessor.ageAdvance(model: "claude-sonnet-4-6", tokens: 1000), 1000)
        XCTAssertEqual(TickProcessor.ageAdvance(model: "claude-opus-4-7",   tokens: 1000), 2000)
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

    func testProcessFiresEnteredCriticalOnce() {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance)
        // Stage HP at zero, then drive the critical state machine via process.
        state.vitals.hp = 0
        let event = UsageEvent(
            timestamp: Date(),
            model: "claude-sonnet-4-6",
            inputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0, outputTokens: 1,
            sessionId: "s1", messageId: "m1", cwd: nil, tools: [], slashCommand: nil
        )
        let (after, results) = TickProcessor.process(event, state: state, deltaTokens: 1)
        XCTAssertEqual(after.vitals.hp, 0)
        XCTAssertTrue(results.contains(.enteredCritical))

        // Second tick from critical state should not re-fire enteredCritical.
        let (_, results2) = TickProcessor.process(event, state: after, deltaTokens: 1)
        XCTAssertFalse(results2.contains(.enteredCritical))
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

@testable import Tokade
import XCTest

final class TickProcessorTests: XCTestCase {
    func testHpDrainRates() {
        XCTAssertEqual(TickProcessor.hpDrain(model: "claude-haiku-4-5", tokens: 10000), 1)
        XCTAssertEqual(TickProcessor.hpDrain(model: "claude-sonnet-4-6", tokens: 10000), 2)
        XCTAssertEqual(TickProcessor.hpDrain(model: "claude-opus-4-7",   tokens: 10000), 5)
        // Unknown models fall back to the moderate rate.
        XCTAssertEqual(TickProcessor.hpDrain(model: "future-model", tokens: 80000), 10)
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

    func testProcessAppliesHpDrainAndAge() {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance)
        state.vitals.hp = 100   // give it room to drain
        let event = UsageEvent(
            timestamp: Date(),
            model: "claude-opus-4-7",
            inputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            outputTokens: 20000,
            sessionId: "s1", messageId: "m1",
            cwd: "/repo",
            tools: ["Bash"],
            slashCommand: nil
        )
        let (after, results) = TickProcessor.process(event, state: state, deltaTokens: 20000)
        // Opus = 1 HP per 2K tokens, 20K → -10 HP.
        XCTAssertEqual(after.vitals.hp, 90)
        // Opus × 1 age point per token × 2 multiplier = 40K age points.
        XCTAssertEqual(after.identity.ageTokens, 40000)
        // Bash drops a dumbbell.
        XCTAssertEqual(after.inventory.items["dumbbell"], 1)
        // Three observable results: HP, age, dumbbell.
        XCTAssertTrue(results.contains(.hpChanged(delta: -10)))
        XCTAssertTrue(results.contains(.itemDropped(itemId: "dumbbell", count: 1)))
    }

    func testProcessFiresEnteredCriticalOnce() {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance)
        state.vitals.hp = 5
        let event = UsageEvent(
            timestamp: Date(),
            model: "claude-opus-4-7",
            inputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0, outputTokens: 20000,
            sessionId: "s1", messageId: "m1", cwd: nil, tools: [], slashCommand: nil
        )
        let (after, results) = TickProcessor.process(event, state: state, deltaTokens: 20000)
        XCTAssertEqual(after.vitals.hp, 0)
        XCTAssertTrue(results.contains(.enteredCritical))

        // Second tick from critical state should not re-fire enteredCritical.
        let (_, results2) = TickProcessor.process(event, state: after, deltaTokens: 20000)
        XCTAssertFalse(results2.contains(.enteredCritical))
    }

    func testProcessFiresDiedOnAgeOut() {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance)
        state.identity.lifespanTokens = 100
        state.identity.ageTokens = 50
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

@testable import Tokade
import XCTest

@MainActor
final class TokenGaidenStoreTests: XCTestCase {
    func testTickIsIdempotentForSameMessage() async {
        let g = TokenGaidenStore()
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        await g.startNewLineage(name: "Boba", appearance: appearance)
        let event = UsageEvent(
            timestamp: Date(),
            model: "claude-opus-4-7",
            inputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0, outputTokens: 4000,
            sessionId: "s1", messageId: "m-stable",
            cwd: nil, tools: ["Bash"], slashCommand: nil
        )

        await g.tick(against: [event])
        let firstHP = g.state?.vitals.hp ?? -1
        let firstAge = g.state?.identity.ageTokens ?? -1
        let firstDumbbells = g.state?.inventory.items["dumbbell"] ?? 0

        // Same event re-read from the JSONL should not double-charge.
        await g.tick(against: [event])
        XCTAssertEqual(g.state?.vitals.hp, firstHP)
        XCTAssertEqual(g.state?.identity.ageTokens, firstAge)
        XCTAssertEqual(g.state?.inventory.items["dumbbell"], firstDumbbells)

        // A new event with the same message but more total tokens (because the
        // assistant streamed more output) accounts the *delta*, not the whole.
        let grown = UsageEvent(
            timestamp: event.timestamp,
            model: event.model,
            inputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0,
            outputTokens: 6000,
            sessionId: "s1", messageId: "m-stable",
            cwd: nil, tools: ["Bash"], slashCommand: nil
        )
        await g.tick(against: [grown])
        // Delta = 2_000 tokens of Opus → 1 more HP drained, 4_000 more age,
        // and a second Bash drop.
        XCTAssertEqual(g.state?.vitals.hp, firstHP - 1)
        XCTAssertEqual(g.state?.identity.ageTokens, firstAge + 4000)
        XCTAssertEqual(g.state?.inventory.items["dumbbell"], firstDumbbells + 1)

        await g.eraseHistory()
    }

    func testCharacterCreatorBootstrapsNewLineage() async {
        let g = TokenGaidenStore()
        XCTAssertNil(g.state)
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "peach", irisSwatch: "green",
            hairStyle: "spiky", hairSwatch: "magenta"
        )
        await g.startNewLineage(name: "Maple", appearance: appearance)
        XCTAssertEqual(g.state?.identity.name, "Maple")
        XCTAssertEqual(g.state?.identity.appearance.hairStyle, "spiky")
        await g.eraseHistory()
        XCTAssertNil(g.state)
    }
}

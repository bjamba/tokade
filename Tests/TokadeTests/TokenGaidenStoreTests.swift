@testable import Tokade
import XCTest

@MainActor
final class TokenGaidenStoreTests: XCTestCase {
    func testTickIsIdempotentForSameMessage() async {
        let g = TokenGaidenStore(notifier: nil)
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        await g.startNewLineage(name: "Boba", appearance: appearance)
        let event = UsageEvent(
            timestamp: Date(),
            model: "claude-opus-4-7",
            inputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0,
            outputTokens: 200_000,
            sessionId: "s1", messageId: "m-stable",
            cwd: nil, tools: ["Bash"], slashCommand: nil
        )

        await g.tick(against: [event])
        let firstToolProgress = g.state?.inventory.toolProgress?["dumbbell"] ?? 0

        // Same event re-read from the JSONL should not double-count tool
        // progress (the per-event accounting key prevents replay).
        await g.tick(against: [event])
        XCTAssertEqual(g.state?.inventory.toolProgress?["dumbbell"] ?? 0,
                       firstToolProgress)

        // A new event with the same message but more total tokens (the
        // assistant streamed more output) advances tool progress by one
        // because tool calls are counted per delta, not per event.
        let grown = UsageEvent(
            timestamp: event.timestamp,
            model: event.model,
            inputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0,
            outputTokens: 300_000,
            sessionId: "s1", messageId: "m-stable",
            cwd: nil, tools: ["Bash"], slashCommand: nil
        )
        await g.tick(against: [grown])
        XCTAssertEqual(g.state?.inventory.toolProgress?["dumbbell"] ?? 0,
                       firstToolProgress + 1)

        await g.eraseHistory()
    }

    func testCharacterCreatorBootstrapsNewLineage() async {
        let g = TokenGaidenStore(notifier: nil)
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

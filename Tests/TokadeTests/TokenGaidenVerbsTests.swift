@testable import Tokade
import XCTest

/// Covers the themed slash-command drops and tool verb flavor added for
/// issue #41. These are pure helpers in `TickProcessor`.
final class TokenGaidenVerbsTests: XCTestCase {
    // MARK: - slashDrop(for:)

    func testSlashDropTestCommandDropsHealItem() {
        XCTAssertEqual(TickProcessor.slashDrop(for: "/run-tests"), "bread")
        XCTAssertEqual(TickProcessor.slashDrop(for: "test"), "bread")
        // Case-insensitive matching.
        XCTAssertEqual(TickProcessor.slashDrop(for: "/Integration-TEST"), "bread")
    }

    func testSlashDropReviewCommandDropsSpPotion() {
        XCTAssertEqual(TickProcessor.slashDrop(for: "/review"), "small-sp-potion")
        XCTAssertEqual(TickProcessor.slashDrop(for: "code-review"), "small-sp-potion")
    }

    func testSlashDropOtherCommandPreservesDefaultSpPotion() {
        XCTAssertEqual(TickProcessor.slashDrop(for: "/compact"), "small-sp-potion")
        XCTAssertEqual(TickProcessor.slashDrop(for: ""), "small-sp-potion")
        XCTAssertEqual(TickProcessor.slashDrop(for: "/clear"), "small-sp-potion")
    }

    // MARK: - toolVerb(for:)

    func testToolVerbForge() {
        XCTAssertEqual(TickProcessor.toolVerb(for: "Bash"), "forge")
    }

    func testToolVerbConstruct() {
        XCTAssertEqual(TickProcessor.toolVerb(for: "Edit"), "construct")
        XCTAssertEqual(TickProcessor.toolVerb(for: "Write"), "construct")
        XCTAssertEqual(TickProcessor.toolVerb(for: "NotebookEdit"), "construct")
    }

    func testToolVerbScout() {
        XCTAssertEqual(TickProcessor.toolVerb(for: "Grep"), "scout")
        XCTAssertEqual(TickProcessor.toolVerb(for: "Read"), "scout")
        XCTAssertEqual(TickProcessor.toolVerb(for: "Glob"), "scout")
    }

    func testToolVerbResearch() {
        XCTAssertEqual(TickProcessor.toolVerb(for: "WebFetch"), "research")
        XCTAssertEqual(TickProcessor.toolVerb(for: "WebSearch"), "research")
    }

    func testToolVerbNilForUnmappedFamilies() {
        XCTAssertNil(TickProcessor.toolVerb(for: "Task"))
        XCTAssertNil(TickProcessor.toolVerb(for: "TodoWrite"))
        XCTAssertNil(TickProcessor.toolVerb(for: "SomeMCPTool"))
        XCTAssertNil(TickProcessor.toolVerb(for: ""))
    }
}

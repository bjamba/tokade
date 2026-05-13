import XCTest
@testable import Tokade

/// Sequence-extension aggregations on `[UsageEvent]` drive every chart.
/// A regression here silently miscounts tokens in production. Tests are
/// constructed against fixed event arrays so any change to grouping/sorting
/// is caught.
final class ModelsExtensionsTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)  // arbitrary

    private func event(model: String = "claude-opus-4-7",
                       tokens: Int = 100,
                       cwd: String? = "/Users/me/proj",
                       tools: [String] = [],
                       slash: String? = nil,
                       offsetSec: TimeInterval = 0) -> UsageEvent {
        UsageEvent(
            timestamp: fixedDate.addingTimeInterval(offsetSec),
            model: model,
            inputTokens: tokens / 4,
            cacheCreationTokens: tokens / 4,
            cacheReadTokens: tokens / 4,
            outputTokens: tokens / 4,
            sessionId: "session-x",
            messageId: UUID().uuidString,
            cwd: cwd,
            tools: tools,
            slashCommand: slash
        )
    }

    // MARK: grandTotal

    func testGrandTotalSumsAllFourBuckets() {
        let e = UsageEvent(
            timestamp: fixedDate, model: "x",
            inputTokens: 1, cacheCreationTokens: 10,
            cacheReadTokens: 100, outputTokens: 1000,
            sessionId: nil, messageId: nil, cwd: nil, tools: [], slashCommand: nil
        )
        XCTAssertEqual(e.grandTotal, 1111)
    }

    // MARK: within

    func testWithinExcludesEventsBeforeCutoff() {
        let now = Date()
        let events = [
            event(offsetSec: now.timeIntervalSince(fixedDate) - 7200),   // 2h ago — in
            event(offsetSec: now.timeIntervalSince(fixedDate) - 21600),  // 6h ago — out
        ]
        let within5h = events.within(5 * 3600, of: now)
        XCTAssertEqual(within5h.count, 1)
    }

    // MARK: groupedByModel

    func testGroupedByModelExcludesSynthetic() {
        let events = [
            event(model: "claude-opus-4-7", tokens: 1000),
            event(model: "<synthetic>", tokens: 999),
            event(model: "claude-sonnet-4-6", tokens: 500),
        ]
        let grouped = events.groupedByModel()
        XCTAssertEqual(grouped.count, 2)
        XCTAssertFalse(grouped.contains { $0.model == "<synthetic>" })
    }

    func testGroupedByModelSortsByTotalDescending() {
        let events = [
            event(model: "claude-haiku-4-5", tokens: 100),
            event(model: "claude-opus-4-7", tokens: 1000),
            event(model: "claude-sonnet-4-6", tokens: 500),
        ]
        let grouped = events.groupedByModel()
        XCTAssertEqual(grouped[0].model, "claude-opus-4-7")
        XCTAssertEqual(grouped[1].model, "claude-sonnet-4-6")
        XCTAssertEqual(grouped[2].model, "claude-haiku-4-5")
    }

    // MARK: groupedByProject

    func testGroupedByProjectUsesBasenameOfCwd() {
        let events = [
            event(cwd: "/Users/me/foo/bar"),
            event(cwd: "/Users/me/foo/bar"),
            event(cwd: "/Users/me/other"),
        ]
        let grouped = events.groupedByProject()
        XCTAssertEqual(grouped.first?.project, "bar")
        XCTAssertEqual(grouped.first?.total, 200)
    }

    func testGroupedByProjectShowsDashForNilCwd() {
        let events = [event(cwd: nil)]
        let grouped = events.groupedByProject()
        XCTAssertEqual(grouped.first?.project, "—")
    }

    // MARK: toolCallCounts

    func testToolCallCountsAggregatesAcrossEvents() {
        let events = [
            event(tools: ["Bash", "Edit"]),
            event(tools: ["Bash", "Bash"]),
            event(tools: ["Read"]),
        ]
        let counts = Dictionary(uniqueKeysWithValues: events.toolCallCounts().map { ($0.tool, $0.count) })
        XCTAssertEqual(counts["Bash"], 3)
        XCTAssertEqual(counts["Edit"], 1)
        XCTAssertEqual(counts["Read"], 1)
    }

    // MARK: groupedBySlashCommand

    func testGroupedBySlashCommandSeparatesNoCommandBucket() {
        let events = [
            event(tokens: 400, slash: "draft-me"),
            event(tokens: 200, slash: "draft-me"),
            event(tokens: 1000, slash: nil),
            event(tokens: 300, slash: "teach-me"),
        ]
        let result = events.groupedBySlashCommand()
        XCTAssertEqual(result.noCommand, 1000)
        var dict: [String: Int] = [:]
        for row in result.commands { dict[row.name] = row.total }
        XCTAssertEqual(dict["draft-me"], 600)
        XCTAssertEqual(dict["teach-me"], 300)
    }

    func testGroupedBySlashCommandExcludesSynthetic() {
        let events = [
            event(model: "<synthetic>", tokens: 1000, slash: "draft-me"),
            event(tokens: 100, slash: "draft-me"),
        ]
        let result = events.groupedBySlashCommand()
        XCTAssertEqual(result.commands.first?.total, 100)
    }

    // MARK: stacked variants

    func testStackedByProjectAndModelProducesOneRowPerPair() {
        let events = [
            event(model: "claude-opus-4-7",   tokens: 100, cwd: "/p/a"),
            event(model: "claude-sonnet-4-6", tokens: 200, cwd: "/p/a"),
            event(model: "claude-opus-4-7",   tokens: 50,  cwd: "/p/b"),
        ]
        let rows = events.stackedByProjectAndModel()
        XCTAssertEqual(rows.count, 3)
        let aOpus = rows.first { $0.category == "a" && $0.model == "claude-opus-4-7" }
        XCTAssertEqual(aOpus?.value, 100)
    }
}

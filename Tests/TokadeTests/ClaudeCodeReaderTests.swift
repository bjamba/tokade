import XCTest
@testable import Tokade

/// The JSONL parser is the boundary between Claude Code's on-disk format and
/// Tokade's domain model. Schema drift here would silently zero out
/// utilization without crashing.
final class ClaudeCodeReaderTests: XCTestCase {

    /// Write a JSONL fixture to a temp dir Tokade can read with the same
    /// directory enumeration it uses in production.
    private func makeFixture(lines: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokade-tests-\(UUID().uuidString)")
        let projects = dir.appendingPathComponent("project-a")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let file = projects.appendingPathComponent("session.jsonl")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return dir
    }

    func testParsesAssistantUsageBlock() async throws {
        let line = """
        {"type":"assistant","timestamp":"2026-05-09T18:00:00Z","sessionId":"s1","message":{"id":"m1","model":"claude-opus-4-7","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":100,"output_tokens":5}}}
        """
        let dir = try makeFixture(lines: [line])
        defer { try? FileManager.default.removeItem(at: dir) }

        let reader = ClaudeCodeReader(projectsURL: dir)
        let events = await reader.readAllEvents()

        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.model, "claude-opus-4-7")
        XCTAssertEqual(e.inputTokens, 10)
        XCTAssertEqual(e.cacheCreationTokens, 20)
        XCTAssertEqual(e.cacheReadTokens, 100)
        XCTAssertEqual(e.outputTokens, 5)
        XCTAssertEqual(e.sessionId, "s1")
        XCTAssertEqual(e.messageId, "m1")
    }

    func testSkipsMalformedLinesWithoutCrashing() async throws {
        let lines = [
            "this is not json",
            """
            {"type":"assistant","timestamp":"2026-05-09T18:00:00Z","message":{"model":"claude-opus-4-7","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
            """,
            "",
            "{}"
        ]
        let dir = try makeFixture(lines: lines)
        defer { try? FileManager.default.removeItem(at: dir) }

        let reader = ClaudeCodeReader(projectsURL: dir)
        let events = await reader.readAllEvents()
        XCTAssertEqual(events.count, 1)
    }

    func testIgnoresNonAssistantMessages() async throws {
        let userLine = """
        {"type":"user","timestamp":"2026-05-09T18:00:00Z","sessionId":"s1","cwd":"/tmp/proj","message":{"role":"user","content":"hi"}}
        """
        let permissionLine = """
        {"type":"permission-mode","permissionMode":"default","sessionId":"s1"}
        """
        let dir = try makeFixture(lines: [userLine, permissionLine])
        defer { try? FileManager.default.removeItem(at: dir) }

        let reader = ClaudeCodeReader(projectsURL: dir)
        let events = await reader.readAllEvents()
        XCTAssertEqual(events.count, 0)
    }

    func testAttachesCwdFromPriorUserMessage() async throws {
        let userLine = """
        {"type":"user","timestamp":"2026-05-09T18:00:00Z","sessionId":"s1","cwd":"/tmp/myproj","message":{"role":"user","content":"hi"}}
        """
        let assistantLine = """
        {"type":"assistant","timestamp":"2026-05-09T18:01:00Z","sessionId":"s1","message":{"id":"m1","model":"claude-opus-4-7","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
        """
        let dir = try makeFixture(lines: [userLine, assistantLine])
        defer { try? FileManager.default.removeItem(at: dir) }

        let reader = ClaudeCodeReader(projectsURL: dir)
        let events = await reader.readAllEvents()
        XCTAssertEqual(events.first?.cwd, "/tmp/myproj")
    }

    func testAttachesSlashCommandFromPriorLastPrompt() async throws {
        let lastPromptLine = """
        {"type":"last-prompt","lastPrompt":"/draft-me a cover letter","sessionId":"s1"}
        """
        let assistantLine = """
        {"type":"assistant","timestamp":"2026-05-09T18:01:00Z","sessionId":"s1","message":{"id":"m1","model":"claude-opus-4-7","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
        """
        let dir = try makeFixture(lines: [lastPromptLine, assistantLine])
        defer { try? FileManager.default.removeItem(at: dir) }

        let reader = ClaudeCodeReader(projectsURL: dir)
        let events = await reader.readAllEvents()
        XCTAssertEqual(events.first?.slashCommand, "draft-me")
    }

    func testExtractsToolUseNamesFromContent() async throws {
        let assistantLine = """
        {"type":"assistant","timestamp":"2026-05-09T18:01:00Z","sessionId":"s1","message":{"id":"m1","model":"claude-opus-4-7","content":[{"type":"text","text":"ok"},{"type":"tool_use","name":"Bash"},{"type":"tool_use","name":"Edit"}],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
        """
        let dir = try makeFixture(lines: [assistantLine])
        defer { try? FileManager.default.removeItem(at: dir) }

        let reader = ClaudeCodeReader(projectsURL: dir)
        let events = await reader.readAllEvents()
        XCTAssertEqual(events.first?.tools, ["Bash", "Edit"])
    }

    func testDedupesByMessageIdAcrossFiles() async throws {
        let line = """
        {"type":"assistant","timestamp":"2026-05-09T18:00:00Z","sessionId":"s1","message":{"id":"m-dup","model":"claude-opus-4-7","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
        """
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokade-tests-dedup-\(UUID().uuidString)")
        let p1 = dir.appendingPathComponent("a")
        let p2 = dir.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: p1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: p2, withIntermediateDirectories: true)
        try line.write(to: p1.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
        try line.write(to: p2.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let reader = ClaudeCodeReader(projectsURL: dir)
        let events = await reader.readAllEvents()
        XCTAssertEqual(events.count, 1)
    }

    func testReturnsEmptyForMissingDirectory() async throws {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        let reader = ClaudeCodeReader(projectsURL: bogus)
        let events = await reader.readAllEvents()
        XCTAssertEqual(events.count, 0)
    }
}

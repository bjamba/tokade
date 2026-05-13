@testable import Tokade
import XCTest

/// `ClaudeCodeReader` caches per-file parse results keyed by mtime so that
/// 30-second polls don't re-parse hundreds of unchanged files. Tests
/// verify cold start, steady-state hit, mtime invalidation, and pruning
/// of files that disappear between polls.
final class ClaudeCodeReaderCacheTests: XCTestCase {
    private let sampleAssistantLine = """
    {"type":"assistant","timestamp":"2026-05-09T18:00:00Z","sessionId":"s1","message":{"id":"m1","model":"claude-opus-4-7","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
    """

    private func makeFixtureDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokade-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ line: String, to url: URL, mtime: Date) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try line.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
    }

    func testColdStartParsesAllFiles() async throws {
        let dir = try makeFixtureDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(sampleAssistantLine, to: dir.appendingPathComponent("a/s.jsonl"), mtime: Date())
        try write(sampleAssistantLine, to: dir.appendingPathComponent("b/s.jsonl"), mtime: Date())

        let reader = ClaudeCodeReader(projectsURL: dir)
        _ = await reader.readAllEvents()
        let count = await reader.lastParseCount
        XCTAssertEqual(count, 2, "cold start should parse both files")
    }

    func testSecondPollHitsCache() async throws {
        let dir = try makeFixtureDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(sampleAssistantLine, to: dir.appendingPathComponent("a/s.jsonl"), mtime: Date())

        let reader = ClaudeCodeReader(projectsURL: dir)
        _ = await reader.readAllEvents()
        _ = await reader.readAllEvents()
        let count = await reader.lastParseCount
        XCTAssertEqual(count, 0, "second poll with unchanged files should parse nothing")
    }

    func testMtimeBumpForcesReparse() async throws {
        let dir = try makeFixtureDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("a/s.jsonl")
        try write(sampleAssistantLine, to: url, mtime: Date(timeIntervalSince1970: 1_700_000_000))

        let reader = ClaudeCodeReader(projectsURL: dir)
        _ = await reader.readAllEvents()
        // Bump mtime forward without changing content. Cache should invalidate.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_999)],
            ofItemAtPath: url.path
        )
        _ = await reader.readAllEvents()
        let count = await reader.lastParseCount
        XCTAssertEqual(count, 1, "mtime advance should force re-parse")
    }

    func testCachePrunesOnDeletedFile() async throws {
        let dir = try makeFixtureDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a/s.jsonl")
        let b = dir.appendingPathComponent("b/s.jsonl")
        try write(sampleAssistantLine, to: a, mtime: Date())
        try write(sampleAssistantLine, to: b, mtime: Date())

        let reader = ClaudeCodeReader(projectsURL: dir)
        _ = await reader.readAllEvents()
        try FileManager.default.removeItem(at: b)
        _ = await reader.readAllEvents()
        // After pruning, modifying `a` should be the only re-parse work.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: a.path
        )
        _ = await reader.readAllEvents()
        let count = await reader.lastParseCount
        XCTAssertEqual(count, 1, "only a should re-parse; b is gone from disk and cache")
    }
}

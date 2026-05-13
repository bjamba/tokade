@testable import Tokade
import XCTest

/// Archive files contain `cwd` paths from the user's Claude Code sessions
/// (mild PII). The user's promise in the README is that these files are
/// 0600 — owner-only read/write — so a multi-user macOS can't sniff them
/// via another local account.
final class EventArchivePermissionsTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokade-archive-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func event() -> UsageEvent {
        UsageEvent(
            timestamp: Date(),
            model: "claude-sonnet-4-6",
            inputTokens: 1, cacheCreationTokens: 0, cacheReadTokens: 0, outputTokens: 1,
            sessionId: "s1", messageId: UUID().uuidString,
            cwd: "/tmp/proj", tools: [], slashCommand: nil
        )
    }

    func testEventArchiveFileIs0600() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let archive = EventArchive(directory: dir)
        let written = await archive.archive([event()])
        XCTAssertGreaterThan(written, 0)

        let fileURL = dir.appendingPathComponent("events.jsonl")
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(perms, 0o600, "expected 0600, got \(String(perms, radix: 8))")
    }

    func testSnapshotArchiveFileIs0600() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let archive = SnapshotArchive(directory: dir)
        let snap = UsageSnapshot(
            t: Date(),
            snapshot: RateLimitSnapshot(
                fiveHour: RateLimitWindow(usedPercentage: 50, resetsAt: Date()),
                sevenDay: nil,
                modelDisplayName: nil, modelId: nil, sessionId: "x",
                capturedAt: Date()
            )
        )
        await archive.append(snap)

        let fileURL = dir.appendingPathComponent("snapshots.jsonl")
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(perms, 0o600, "expected 0600, got \(String(perms, radix: 8))")
    }
}

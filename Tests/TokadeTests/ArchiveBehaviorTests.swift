@testable import Tokade
import XCTest

/// Behavioral guards for the durable archive contracts (issues #32, #33).
/// The archives are an append-only user contract — silently dropping events or
/// window-start snapshots corrupts the historical record these tests defend.
final class ArchiveBehaviorTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokade-archive-behavior-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func event(at ts: Date, id: String) -> UsageEvent {
        UsageEvent(
            timestamp: ts,
            model: "claude-sonnet-4-6",
            inputTokens: 1, cacheCreationTokens: 0, cacheReadTokens: 0, outputTokens: 1,
            sessionId: "s1", messageId: id,
            cwd: "/tmp/proj", tools: [], slashCommand: nil
        )
    }

    // MARK: - #32 — same-timestamp events are not dropped

    func testSameTimestampDistinctEventsAreBothArchived() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = EventArchive(directory: dir)

        let ts = Date()
        // Poll 1 sees only event A.
        let w1 = await archive.archive([event(at: ts, id: "A")])
        XCTAssertEqual(w1, 1)

        // Poll 2 sees A again (already archived) plus a *distinct* event B at
        // the exact same timestamp. B must still be archived — the old strict
        // `>` high-water dropped it forever.
        let w2 = await archive.archive([event(at: ts, id: "A"), event(at: ts, id: "B")])
        XCTAssertEqual(w2, 1, "the distinct same-timestamp event B should be archived")

        let (count, _) = await archive.status()
        XCTAssertEqual(count, 2, "both A and B should be on disk")
    }

    func testHighWaterStillSkipsAlreadyArchivedEvents() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = EventArchive(directory: dir)

        let ts = Date()
        _ = await archive.archive([event(at: ts, id: "A")])
        // Replaying the identical event must not double-write.
        let again = await archive.archive([event(at: ts, id: "A")])
        XCTAssertEqual(again, 0)
        let (count, _) = await archive.status()
        XCTAssertEqual(count, 1)
    }

    func testMetaSurvivesReinitAndStillDedupesBoundary() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ts = Date()

        let first = EventArchive(directory: dir)
        _ = await first.archive([event(at: ts, id: "A")])

        // A fresh instance reads the persisted meta (date + boundary ids).
        let second = EventArchive(directory: dir)
        let replay = await second.archive([event(at: ts, id: "A")])
        XCTAssertEqual(replay, 0, "boundary id A should persist across re-init")
        let newDistinct = await second.archive([event(at: ts, id: "C")])
        XCTAssertEqual(newDistinct, 1, "a new distinct same-timestamp event still lands")
    }

    // MARK: - #33 — window rollover snapshots are not deduped away

    private func snapshot(five: Double, resets: Date, session: String) -> UsageSnapshot {
        UsageSnapshot(
            t: Date(),
            snapshot: RateLimitSnapshot(
                fiveHour: RateLimitWindow(usedPercentage: five, resetsAt: resets),
                sevenDay: nil,
                modelDisplayName: nil, modelId: nil, sessionId: session,
                capturedAt: Date()
            )
        )
    }

    func testWindowRolloverWithSamePercentStillWrites() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = SnapshotArchive(directory: dir)

        let windowA = Date(timeIntervalSince1970: 1_000_000)
        let windowB = windowA.addingTimeInterval(5 * 3600) // next 5h window

        // Same 5h% and same session, but a new window (different resetsAt).
        await archive.append(snapshot(five: 4.0, resets: windowA, session: "s"))
        await archive.append(snapshot(five: 4.0, resets: windowB, session: "s"))

        let all = await archive.readAll()
        XCTAssertEqual(all.count, 2, "the new window's start anchor must persist")
    }

    func testTrulyIdenticalSnapshotIsStillDeduped() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = SnapshotArchive(directory: dir)

        let window = Date(timeIntervalSince1970: 2_000_000)
        await archive.append(snapshot(five: 12.0, resets: window, session: "s"))
        await archive.append(snapshot(five: 12.0, resets: window, session: "s"))

        let all = await archive.readAll()
        XCTAssertEqual(all.count, 1, "identical samples should still dedupe")
    }
}

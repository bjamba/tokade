import Foundation
import os

/// Compact archived event. Field names abbreviated to reduce file size.
struct ArchivedEvent: Codable {
    let t: Date              // timestamp
    let m: String            // model
    let i: Int               // input tokens
    let cc: Int              // cache creation
    let cr: Int              // cache read
    let o: Int               // output
    let s: String?           // sessionId
    let id: String?          // messageId
    let cwd: String?
    let tools: [String]?
    let cmd: String?         // slashCommand

    init(_ e: UsageEvent) {
        t = e.timestamp
        m = e.model
        i = e.inputTokens
        cc = e.cacheCreationTokens
        cr = e.cacheReadTokens
        o = e.outputTokens
        s = e.sessionId
        id = e.messageId
        cwd = e.cwd
        tools = e.tools.isEmpty ? nil : e.tools
        cmd = e.slashCommand
    }
}

/// Append-only archive of every parsed UsageEvent. Survives JSONL deletion.
/// Tracks the high-water timestamp so each poll only writes new events.
actor EventArchive {
    private let directory: URL
    private let fileURL: URL
    private let metaURL: URL
    private let encoder: JSONEncoder
    private var lastArchived: Date?
    /// messageIds already archived AT the `lastArchived` timestamp. Lets us
    /// admit a later-arriving distinct event that shares that exact timestamp
    /// without re-appending the ones already written (issue #32).
    private var boundaryIds: Set<String> = []
    private let log = Logger(subsystem: "com.bjamba.tokade", category: "EventArchive")

    init(directory: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".tokade/history")) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("events.jsonl")
        self.metaURL = directory.appendingPathComponent("events.last")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        let meta = EventArchive.readMeta(metaURL)
        self.lastArchived = meta.date
        self.boundaryIds = meta.ids
    }

    /// Append events whose timestamp is newer than the last archived high-water.
    /// Returns the number of new events written.
    @discardableResult
    func archive(_ events: [UsageEvent]) -> Int {
        let cutoff = lastArchived ?? .distantPast
        // Admit events strictly after the high-water, plus distinct events that
        // share the exact high-water timestamp but weren't archived yet (deduped
        // by messageId). Fixes silent loss of same-timestamp events (issue #32).
        // Same-timestamp events without a messageId remain best-effort skipped
        // to avoid re-appending them on every relaunch.
        let toWrite = events.filter { e in
            if e.timestamp > cutoff { return true }
            if e.timestamp == cutoff, let id = e.messageId, !boundaryIds.contains(id) { return true }
            return false
        }
        guard !toWrite.isEmpty else { return 0 }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            log.warning("createDirectory failed for \(self.directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return 0
        }

        var data = Data()
        for e in toWrite.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let line = try? encoder.encode(ArchivedEvent(e)) else {
                log.warning("encode skipped one ArchivedEvent")
                continue
            }
            data.append(line)
            data.append(0x0A)
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                do {
                    try handle.write(contentsOf: data)
                } catch {
                    log.warning("write failed: \(error.localizedDescription, privacy: .public)")
                    return 0
                }
            } else {
                log.warning("FileHandle(forWritingTo:) failed for \(self.fileURL.path, privacy: .public)")
                return 0
            }
        } else {
            FileManager.default.createFile(
                atPath: fileURL.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            )
        }
        // Ensure 0600 even if the file existed previously (e.g. from a pre-0.2 install).
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                ofItemAtPath: fileURL.path)

        let newest = toWrite.map(\.timestamp).max() ?? Date()
        let newestIds = Set(toWrite.filter { $0.timestamp == newest }.compactMap(\.messageId))
        if newest == lastArchived {
            // Still at the same boundary timestamp — accumulate the new ids.
            boundaryIds.formUnion(newestIds)
        } else {
            boundaryIds = newestIds
        }
        lastArchived = newest
        EventArchive.writeMeta(metaURL, date: newest, ids: boundaryIds)
        return toWrite.count
    }

    /// Return total event count and high-water mark (for diagnostics).
    func status() -> (count: Int, lastArchived: Date?) {
        let count: Int = {
            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else { return 0 }
            return text.split(separator: "\n", omittingEmptySubsequences: true).count
        }()
        return (count, lastArchived)
    }

    /// Erase the archive. Used by the "Erase history…" action in the UI.
    /// Reset the in-memory high-water mark so a subsequent `archive()` will
    /// re-archive everything from JSONL on next poll.
    func erase() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: metaURL)
        lastArchived = nil
        boundaryIds = []
    }

    /// `ts` is stored as `timeIntervalSinceReferenceDate` — unlike
    /// `timeIntervalSince1970`, reconstructing it involves no offset arithmetic,
    /// so the high-water Date round-trips bit-for-bit. That exactness is what
    /// makes the same-timestamp boundary dedup (#32) survive a relaunch.
    private struct Meta: Codable {
        let ts: TimeInterval
        let ids: [String]
    }

    /// Reads the high-water meta. Supports the legacy bare-TimeInterval format
    /// (pre-#32, stored as `timeIntervalSince1970`) by falling back to it when
    /// JSON decoding fails.
    private static func readMeta(_ url: URL) -> (date: Date?, ids: Set<String>) {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, [])
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let meta = try? JSONDecoder().decode(Meta.self, from: data) {
            return (Date(timeIntervalSinceReferenceDate: meta.ts), Set(meta.ids))
        }
        if let ts = TimeInterval(trimmed) {
            return (Date(timeIntervalSince1970: ts), [])
        }
        return (nil, [])
    }

    private static func writeMeta(_ url: URL, date: Date, ids: Set<String>) {
        let meta = Meta(ts: date.timeIntervalSinceReferenceDate, ids: Array(ids))
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                ofItemAtPath: url.path)
    }
}

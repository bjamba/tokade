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
    private let log = Logger(subsystem: "com.bjamba.tokade", category: "EventArchive")

    init(directory: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".tokade/history")) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("events.jsonl")
        self.metaURL = directory.appendingPathComponent("events.last")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.lastArchived = EventArchive.readMeta(metaURL)
    }

    /// Append events whose timestamp is newer than the last archived high-water.
    /// Returns the number of new events written.
    @discardableResult
    func archive(_ events: [UsageEvent]) -> Int {
        let cutoff = lastArchived ?? .distantPast
        let toWrite = events.filter { $0.timestamp > cutoff }
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
        lastArchived = newest
        EventArchive.writeMeta(metaURL, date: newest)
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
    }

    private static func readMeta(_ url: URL) -> Date? {
        guard let s = try? String(contentsOf: url, encoding: .utf8),
              let ts = TimeInterval(s.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return Date(timeIntervalSince1970: ts)
    }

    private static func writeMeta(_ url: URL, date: Date) {
        let s = String(date.timeIntervalSince1970)
        try? s.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                ofItemAtPath: url.path)
    }
}

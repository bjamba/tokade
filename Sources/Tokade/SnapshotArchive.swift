import Foundation

/// One persisted snapshot of server-side rate-limit state. We append one
/// of these per poll so we can plot true budget utilization (%) over time
/// without depending on raw-token math, which is sensitive to per-model weights.
struct UsageSnapshot: Codable, Hashable {
    let t: Date
    let fiveHour: Double?      // 0–100
    let fiveResetsAt: Date?
    let sevenDay: Double?      // 0–100
    let sevenResetsAt: Date?
    let sessionId: String?
    let modelId: String?

    init(t: Date, snapshot: RateLimitSnapshot) {
        self.t = t
        self.fiveHour = snapshot.fiveHour?.usedPercentage
        self.fiveResetsAt = snapshot.fiveHour?.resetsAt
        self.sevenDay = snapshot.sevenDay?.usedPercentage
        self.sevenResetsAt = snapshot.sevenDay?.resetsAt
        self.sessionId = snapshot.sessionId
        self.modelId = snapshot.modelId
    }
}

actor SnapshotArchive {
    private let directory: URL
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var lastWritten: UsageSnapshot?

    init(directory: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".tokade/history")) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("snapshots.jsonl")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// Append a snapshot. Skips writes that don't change `5h%` or `7d%`
    /// from the most recent record (no point archiving identical samples).
    func append(_ snapshot: UsageSnapshot) {
        if let last = lastWritten,
           last.fiveHour == snapshot.fiveHour,
           last.sevenDay == snapshot.sevenDay,
           last.sessionId == snapshot.sessionId {
            return
        }
        try? FileManager.default.createDirectory(at: directory,
                                                  withIntermediateDirectories: true)
        guard let data = try? encoder.encode(snapshot) else { return }
        var line = data
        line.append(0x0A) // newline

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            FileManager.default.createFile(atPath: fileURL.path, contents: line)
        }
        lastWritten = snapshot
    }

    func readAll() -> [UsageSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        var out: [UsageSnapshot] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let snap = try? decoder.decode(UsageSnapshot.self, from: lineData) else { continue }
            out.append(snap)
        }
        return out
    }
}

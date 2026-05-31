import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    var events: [UsageEvent] = []
    var rateLimits: RateLimitSnapshot?
    var snapshots: [UsageSnapshot] = []
    var lastUpdated: Date?
    var isLoading: Bool = false

    private let reader = ClaudeCodeReader()
    private let statusReader = StatusFileReader()
    private let archive = SnapshotArchive()
    private let eventArchive = EventArchive()
    private var pollingTask: Task<Void, Never>?

    static let fiveHours: TimeInterval = 5 * 3600
    static let sevenDays: TimeInterval = 7 * 24 * 3600

    /// Default matches the app's real cadence (TokadeApp calls every: 3). The
    /// game tick reads the same events every 3s; an mtime cache keeps re-polls cheap.
    func startPolling(every interval: TimeInterval = 3) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func refresh() async {
        isLoading = true
        async let freshEvents = reader.readAllEvents()
        async let snapshot = statusReader.read()
        events = await (freshEvents).sorted { $0.timestamp < $1.timestamp }
        let snap = await snapshot
        rateLimits = snap
        if let snap {
            await archive.append(UsageSnapshot(t: Date(), snapshot: snap))
        }
        snapshots = await archive.readAll()
        await eventArchive.archive(events)
        lastUpdated = Date()
        isLoading = false
    }

    var fiveHourEvents: [UsageEvent] { events.within(Self.fiveHours) }
    var weeklyEvents: [UsageEvent] { events.within(Self.sevenDays) }

    /// True when Claude Code's session-log directory is missing — i.e. the
    /// user doesn't have Claude Code installed, or has never run it.
    /// Used to surface a friendly banner instead of an empty-data state.
    var claudeCodeMissing: Bool {
        let path = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects").path
        return !FileManager.default.fileExists(atPath: path)
    }

    /// Erase the persisted archives plus the in-memory state. Triggered by
    /// the "Erase history…" action in the UI. Does not touch
    /// `~/.claude/projects/` — those belong to Claude Code, not us.
    func eraseHistory() async {
        await eventArchive.erase()
        await archive.erase()
        // Best-effort: also drop last-status.json so a stale snapshot
        // doesn't survive the wipe.
        let statusURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".tokade/last-status.json")
        try? FileManager.default.removeItem(at: statusURL)

        events = []
        rateLimits = nil
        snapshots = []
        lastUpdated = Date()
    }
}

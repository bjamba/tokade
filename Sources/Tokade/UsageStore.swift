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

    func startPolling(every interval: TimeInterval = 30) {
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
        events = (await freshEvents).sorted { $0.timestamp < $1.timestamp }
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
}

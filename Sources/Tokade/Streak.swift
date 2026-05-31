import Foundation

/// Pure streak math for the "used Claude today" daily-login mechanic
/// (issue #46). A streak is the number of consecutive local-calendar days,
/// counting back from the most recent active day, on which the user logged
/// at least one usage event.
///
/// The streak is only "live" when the most recent active day is today or
/// yesterday — letting one full calendar day lapse without using Claude
/// breaks the chain. Both arcade games key a small once-per-day bonus off
/// this, so the logic lives here in one tested place.
enum Streak {
    /// Number of consecutive active days ending at the most recent activity,
    /// provided that activity is recent enough (today or yesterday) for the
    /// streak to count as live.
    ///
    /// Returns `0` when there are no events, or when the last activity is
    /// older than yesterday. Day bucketing uses `calendar.startOfDay(for:)`
    /// so it stays correct across DST transitions (a "day" is a calendar
    /// day, not a fixed 86 400-second window).
    static func currentStreak(
        eventTimestamps: [Date],
        now: Date,
        calendar: Calendar = .current
    ) -> Int {
        guard !eventTimestamps.isEmpty else { return 0 }

        // Collapse every event to the start of its local calendar day, then
        // dedupe — we only care which days had *any* activity.
        let activeDays = Set(eventTimestamps.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)

        // Find the most recent active day. The streak is only live if that
        // day is today or yesterday; a fully-skipped day breaks the chain.
        guard let mostRecent = activeDays.max() else { return 0 }
        let daysSinceMostRecent = calendar.dateComponents(
            [.day], from: mostRecent, to: today
        ).day ?? Int.max
        guard daysSinceMostRecent <= 1 else { return 0 }

        // Walk backward one calendar day at a time from the most recent
        // active day, counting the unbroken run of active days.
        var streak = 0
        var cursor = mostRecent
        while activeDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(
                byAdding: .day, value: -1, to: cursor
            ) else { break }
            cursor = calendar.startOfDay(for: previous)
        }
        return streak
    }
}

@testable import Tokade
import XCTest

/// Coverage for `Streak.currentStreak` — the pure daily-usage streak math
/// behind both arcade games' once-per-day bonus (issue #46).
final class StreakTests: XCTestCase {
    /// A fixed, DST-stable reference calendar in a known time zone so the
    /// day-bucketing assertions are deterministic regardless of where CI
    /// runs. Individual tests that exercise DST swap the time zone.
    private func calendar(_ tzID: String = "America/New_York") -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tzID)!
        return cal
    }

    /// Build a Date at a specific local time for the given calendar.
    private func date(
        _ cal: Calendar, _ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0
    ) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return cal.date(from: c)!
    }

    // MARK: - Degenerate cases

    func testEmptyReturnsZero() {
        let cal = calendar()
        let now = date(cal, 2026, 5, 31)
        XCTAssertEqual(
            Streak.currentStreak(eventTimestamps: [], now: now, calendar: cal),
            0
        )
    }

    func testLastActivityOlderThanYesterdayReturnsZero() {
        let cal = calendar()
        let now = date(cal, 2026, 5, 31, 9)
        // Most recent activity is 3 days ago — chain is dead.
        let events = [
            date(cal, 2026, 5, 26),
            date(cal, 2026, 5, 27),
            date(cal, 2026, 5, 28),
        ]
        XCTAssertEqual(
            Streak.currentStreak(eventTimestamps: events, now: now, calendar: cal),
            0
        )
    }

    // MARK: - Live streaks

    func testSingleDayToday() {
        let cal = calendar()
        let now = date(cal, 2026, 5, 31, 18)
        let events = [date(cal, 2026, 5, 31, 9)]
        XCTAssertEqual(
            Streak.currentStreak(eventTimestamps: events, now: now, calendar: cal),
            1
        )
    }

    func testMultiDayConsecutive() {
        let cal = calendar()
        let now = date(cal, 2026, 5, 31, 20)
        let events = [
            date(cal, 2026, 5, 28, 8),
            date(cal, 2026, 5, 29, 10),
            date(cal, 2026, 5, 30, 23),
            date(cal, 2026, 5, 31, 1),
        ]
        XCTAssertEqual(
            Streak.currentStreak(eventTimestamps: events, now: now, calendar: cal),
            4
        )
    }

    func testMultipleEventsSameDayCountOnce() {
        let cal = calendar()
        let now = date(cal, 2026, 5, 31, 20)
        // Three events today, two yesterday — still a 2-day streak.
        let events = [
            date(cal, 2026, 5, 30, 2),
            date(cal, 2026, 5, 30, 14),
            date(cal, 2026, 5, 31, 8),
            date(cal, 2026, 5, 31, 12),
            date(cal, 2026, 5, 31, 23),
        ]
        XCTAssertEqual(
            Streak.currentStreak(eventTimestamps: events, now: now, calendar: cal),
            2
        )
    }

    func testLastActivityYesterdayStillLive() {
        let cal = calendar()
        // No activity today, but yesterday + the day before are active.
        let now = date(cal, 2026, 5, 31, 9)
        let events = [
            date(cal, 2026, 5, 29, 11),
            date(cal, 2026, 5, 30, 16),
        ]
        XCTAssertEqual(
            Streak.currentStreak(eventTimestamps: events, now: now, calendar: cal),
            2
        )
    }

    // MARK: - Gaps break the streak

    func testGapBreaksStreak() {
        let cal = calendar()
        let now = date(cal, 2026, 5, 31, 20)
        // May 27 + 28 active, then a gap on the 29th, then 30 + 31.
        // Counting back from the most recent active day, the streak is
        // only the unbroken 30–31 run.
        let events = [
            date(cal, 2026, 5, 27, 9),
            date(cal, 2026, 5, 28, 9),
            date(cal, 2026, 5, 30, 9),
            date(cal, 2026, 5, 31, 9),
        ]
        XCTAssertEqual(
            Streak.currentStreak(eventTimestamps: events, now: now, calendar: cal),
            2
        )
    }

    func testUnorderedTimestampsHandled() {
        let cal = calendar()
        let now = date(cal, 2026, 5, 31, 20)
        // Same as the consecutive case but shuffled — order must not matter.
        let events = [
            date(cal, 2026, 5, 31, 1),
            date(cal, 2026, 5, 29, 10),
            date(cal, 2026, 5, 30, 23),
            date(cal, 2026, 5, 28, 8),
        ]
        XCTAssertEqual(
            Streak.currentStreak(eventTimestamps: events, now: now, calendar: cal),
            4
        )
    }

    // MARK: - DST safety

    /// US "spring forward" 2026: clocks jump 02:00 → 03:00 on March 8. The
    /// March 8 local day is only 23 hours long, so fixed-86 400-second
    /// bucketing would miscount. `startOfDay` keeps it correct.
    func testDSTSpringForwardDayBucketing() {
        let cal = calendar() // America/New_York
        // now is March 9 (the day after the short day).
        let now = date(cal, 2026, 3, 9, 12)
        let events = [
            date(cal, 2026, 3, 7, 23, 30), // before the transition
            date(cal, 2026, 3, 8, 1, 30),  // before the 2am jump
            date(cal, 2026, 3, 8, 12, 0),  // after the jump, same local day
            date(cal, 2026, 3, 9, 6, 0),
        ]
        XCTAssertEqual(
            Streak.currentStreak(eventTimestamps: events, now: now, calendar: cal),
            3
        )
    }

    /// US "fall back" 2026: clocks repeat 01:00–02:00 on Nov 1, making that
    /// local day 25 hours long. Two events on either side of the repeated
    /// hour are still the same calendar day.
    func testDSTFallBackDayBucketing() {
        let cal = calendar()
        let now = date(cal, 2026, 11, 1, 20)
        let events = [
            date(cal, 2026, 10, 31, 22),
            date(cal, 2026, 11, 1, 0, 30),
            date(cal, 2026, 11, 1, 19, 0),
        ]
        // Oct 31 + Nov 1 active → 2-day live streak.
        XCTAssertEqual(
            Streak.currentStreak(eventTimestamps: events, now: now, calendar: cal),
            2
        )
    }
}

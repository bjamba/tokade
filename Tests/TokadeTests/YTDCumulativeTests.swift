@testable import Tokade
import XCTest

/// Regression coverage for issue #48: the YTD card's "last 30 day" daily
/// rate inflated in early January. The numerator summed events back 30 days
/// (reaching into the previous December) but the denominator was clamped to
/// the number of days elapsed since Jan 1 — so a few late-December events
/// were divided by 2–3 days, producing an absurd rate. The fix divides by
/// the actual 30-day window span, matching numerator and denominator.
@MainActor
final class YTDCumulativeTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func event(_ date: Date, tokens: Int, model: String = "claude-sonnet-4-6") -> UsageEvent {
        UsageEvent(
            timestamp: date,
            model: model,
            inputTokens: tokens, cacheCreationTokens: 0, cacheReadTokens: 0, outputTokens: 0,
            sessionId: "s", messageId: UUID().uuidString,
            cwd: "/tmp/proj", tools: [], slashCommand: nil
        )
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    /// Early January with the bulk of usage in late December. The trailing
    /// 30-day window spans those December events, so the rate must reflect a
    /// 30-day average — NOT 300k divided by ~3 elapsed-this-year days.
    func testLast30DayRateNotInflatedInEarlyJanuary() {
        let now = date(2026, 1, 3)
        // 300,000 tokens spread across late December (within the 30d window).
        let events = [
            event(date(2025, 12, 28), tokens: 100_000),
            event(date(2025, 12, 29), tokens: 100_000),
            event(date(2025, 12, 30), tokens: 100_000),
        ]

        let rate = YTDCumulativeCard.last30DayRate(events: events, now: now, calendar: cal)

        // Correct: 300k / 30 days = 10k/day. The old buggy behavior would
        // divide by ~2 elapsed days (Jan 1 → Jan 3), yielding ~150k/day.
        XCTAssertEqual(rate, 10000, accuracy: 1.0)
        XCTAssertLessThan(rate, 20000, "30-day rate must not be inflated by the YTD-clamped denominator")
    }

    /// Mid-year sanity: a clean 30-day window with steady usage.
    func testLast30DayRateMidYear() throws {
        let now = date(2026, 6, 30)
        // 30 daily events of 5,000 tokens each within the window.
        var events: [UsageEvent] = []
        for offset in 1 ... 30 {
            let d = try XCTUnwrap(cal.date(byAdding: .day, value: -offset, to: now))
            events.append(event(d, tokens: 5000))
        }

        let rate = YTDCumulativeCard.last30DayRate(events: events, now: now, calendar: cal)
        XCTAssertEqual(rate, 5000, accuracy: 1.0)
    }

    /// Events older than 30 days and synthetic events are excluded.
    func testLast30DayRateExcludesOldAndSyntheticEvents() throws {
        let now = date(2026, 6, 30)
        let events = try [
            event(XCTUnwrap(cal.date(byAdding: .day, value: -5, to: now)), tokens: 60000),
            event(XCTUnwrap(cal.date(byAdding: .day, value: -45, to: now)), tokens: 999_999), // too old
            event(XCTUnwrap(cal.date(byAdding: .day, value: -2, to: now)), tokens: 999_999, model: "<synthetic>"),
        ]

        let rate = YTDCumulativeCard.last30DayRate(events: events, now: now, calendar: cal)
        // Only the 60,000-token event counts: 60k / 30 = 2,000/day.
        XCTAssertEqual(rate, 2000, accuracy: 1.0)
    }
}

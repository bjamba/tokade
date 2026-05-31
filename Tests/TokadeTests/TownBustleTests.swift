@testable import Tokade
import XCTest

/// #45 — guards for `TimeOfDay.bustleFactor`, the usage-driven "bustle"
/// signal that makes Tokeyo Town feel liveliest in the weekday/hour slots
/// where the user actually codes. The factor is layered on top of the
/// wall-clock day/night light, so a wrong value here quietly makes the town
/// busy at the wrong times (or never) — exactly the eyeball-invisible class
/// of bug the math-coverage rule exists to catch.
final class TownBustleTests: XCTestCase {
    private let cal = Calendar.current

    /// A date pinned to a specific weekday/hour so bucketing is deterministic.
    /// Builds from a known reference date and shifts to the target weekday.
    private func date(weekday: Int, hour: Int) -> Date {
        // Anchor on a fixed day (2024-01-07 is a Sunday → weekday 1) and add
        // whole days to reach the requested weekday, then set the hour.
        var comps = DateComponents()
        comps.year = 2024
        comps.month = 1
        comps.day = 6 + weekday // 2024-01-07 == Sunday(1) … 2024-01-13 == Saturday(7)
        comps.hour = hour
        comps.minute = 30
        let d = cal.date(from: comps)!
        XCTAssertEqual(cal.component(.weekday, from: d), weekday, "anchor weekday mismatch")
        return d
    }

    private func event(at ts: Date, total: Int, model: String = "claude-sonnet-4-6") -> UsageEvent {
        UsageEvent(
            timestamp: ts,
            model: model,
            inputTokens: total, cacheCreationTokens: 0, cacheReadTokens: 0, outputTokens: 0,
            sessionId: "s1", messageId: UUID().uuidString,
            cwd: "/tmp/proj", tools: [], slashCommand: nil
        )
    }

    // MARK: - No data → safe quiet default

    func testBustleFactorNoEventsReturnsZero() {
        let now = date(weekday: 3, hour: 14)
        XCTAssertEqual(TimeOfDay.bustleFactor(events: [], now: now), 0.0)
    }

    func testBustleFactorOnlySyntheticEventsReturnsZero() {
        // `<synthetic>` events are excluded from the heatmap bucketing, so a
        // history made entirely of them must read as no usage at all.
        let now = date(weekday: 3, hour: 14)
        let events = [
            event(at: now, total: 9999, model: "<synthetic>"),
            event(at: date(weekday: 5, hour: 9), total: 1234, model: "<synthetic>")
        ]
        XCTAssertEqual(TimeOfDay.bustleFactor(events: events, now: now), 0.0)
    }

    // MARK: - Peak hour → high factor

    func testBustleFactorPeakBucketReturnsOne() {
        let peak = date(weekday: 3, hour: 14) // Tue 14:00
        let events = [
            event(at: peak, total: 1000),
            event(at: date(weekday: 5, hour: 9), total: 100)
        ]
        // "now" sits in the same weekday/hour bucket as the busiest usage.
        XCTAssertEqual(TimeOfDay.bustleFactor(events: events, now: peak), 1.0, accuracy: 1e-9)
    }

    func testBustleFactorAggregatesWithinBucket() {
        // Multiple events in the same weekday/hour bucket sum together, and
        // the peak bucket normalizes to 1.0.
        let busy = date(weekday: 3, hour: 14)
        let quiet = date(weekday: 4, hour: 2)
        let events = [
            event(at: date(weekday: 3, hour: 14), total: 300),
            event(at: busy, total: 700), // same Tue-14 bucket → 1000 total
            event(at: quiet, total: 250) // a lesser bucket
        ]
        XCTAssertEqual(TimeOfDay.bustleFactor(events: events, now: busy), 1.0, accuracy: 1e-9)
        // The quiet bucket is 250/1000 = 0.25 of the peak.
        XCTAssertEqual(TimeOfDay.bustleFactor(events: events, now: quiet), 0.25, accuracy: 1e-9)
    }

    // MARK: - Off / dead hour → low factor

    func testBustleFactorDeadHourReturnsZero() {
        let peak = date(weekday: 3, hour: 14)
        let events = [event(at: peak, total: 1000)]
        // 3 AM Saturday has no usage at all → fully calm.
        let dead = date(weekday: 7, hour: 3)
        XCTAssertEqual(TimeOfDay.bustleFactor(events: events, now: dead), 0.0)
    }

    func testBustleFactorMidBucketIsProportional() {
        let peak = date(weekday: 3, hour: 14) // 1000 tokens → peak
        let mid = date(weekday: 2, hour: 20) // 400 tokens → 0.4 of peak
        let events = [
            event(at: peak, total: 1000),
            event(at: mid, total: 400)
        ]
        XCTAssertEqual(TimeOfDay.bustleFactor(events: events, now: mid), 0.4, accuracy: 1e-9)
    }

    // MARK: - Bounds

    func testBustleFactorIsAlwaysWithinUnitInterval() {
        let peak = date(weekday: 3, hour: 14)
        let events = [
            event(at: peak, total: 5_000_000),
            event(at: date(weekday: 1, hour: 0), total: 1)
        ]
        for weekday in 1 ... 7 {
            for hour in [0, 6, 14, 23] {
                let f = TimeOfDay.bustleFactor(events: events, now: date(weekday: weekday, hour: hour))
                XCTAssertGreaterThanOrEqual(f, 0.0)
                XCTAssertLessThanOrEqual(f, 1.0)
            }
        }
    }
}

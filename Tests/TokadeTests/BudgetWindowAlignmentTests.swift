@testable import Tokade
import XCTest

/// Regression coverage for #44: past-window budget bars must align to the
/// recorded snapshot reset-times, not the forward-projected `currentResetsAt`,
/// so a rollover with no fresh statusline write doesn't misplace server-truth.
final class BudgetWindowAlignmentTests: XCTestCase {
    private let fiveHours: TimeInterval = 5 * 3600

    /// Baseline: with no recorded resets, ends are just the projected grid.
    func testWindowEndsWithoutRecordedResetsUsesProjection() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let ends = PastWindowsBudgetCard.windowEnds(
            currentResetsAt: now,
            recordedResets: [],
            windowCount: 3
        )
        XCTAssertEqual(ends.count, 3)
        XCTAssertEqual(ends[0], now)
        XCTAssertEqual(ends[1], now.addingTimeInterval(-fiveHours))
        XCTAssertEqual(ends[2], now.addingTimeInterval(-2 * fiveHours))
    }

    /// The core #44 case. A window rolled over but no fresh statusline landed,
    /// so `effectiveFiveHourResetsAt` projected `currentResetsAt` forward. The
    /// snapshots on disk are keyed on the *old* server reset-times, which are
    /// offset from the projected grid by a few minutes. Each completed window's
    /// boundary must snap back onto the reset-time its snapshots belong to.
    func testRolloverWithoutFreshStatuslineSnapsToRecordedResets() {
        // Projected current reset (forward-advanced by the projection logic).
        let current = Date(timeIntervalSince1970: 2_000_000)
        // Recorded server resets for the two just-completed windows, drifted ~7
        // minutes off the projected 5h grid (servers aren't 5h-aligned to each
        // other across cycles).
        let drift: TimeInterval = 7 * 60
        let recordedPrev = current.addingTimeInterval(-fiveHours + drift)
        let recordedPrev2 = current.addingTimeInterval(-2 * fiveHours - drift)

        let ends = PastWindowsBudgetCard.windowEnds(
            currentResetsAt: current,
            recordedResets: [recordedPrev, recordedPrev2],
            windowCount: 3
        )

        // In-progress window: no recorded reset near it, keeps the projection.
        XCTAssertEqual(ends[0], current, "current window must stay distinguishable")
        // Completed windows snap exactly onto the recorded reset-times, so
        // perWindow[end] lookups hit and server-truth bars align.
        XCTAssertEqual(ends[1], recordedPrev)
        XCTAssertEqual(ends[2], recordedPrev2)
    }

    /// A recorded reset further than the tolerance must NOT be snapped — that
    /// would yank an unrelated window's snapshot into the wrong slot.
    func testRecordedResetBeyondToleranceIsNotSnapped() {
        let current = Date(timeIntervalSince1970: 3_000_000)
        // ~2h off the projected boundary: a different window, not a drift.
        let farReset = current.addingTimeInterval(-fiveHours + 2 * 3600)
        let ends = PastWindowsBudgetCard.windowEnds(
            currentResetsAt: current,
            recordedResets: [farReset],
            windowCount: 2,
            tolerance: 30 * 60
        )
        XCTAssertEqual(ends[1], current.addingTimeInterval(-fiveHours),
                       "out-of-tolerance reset must not hijack the boundary")
    }

    /// When two recorded resets sit near the same projected boundary, snap to
    /// the closest one (deterministic, no double-assignment confusion).
    func testSnapsToNearestRecordedReset() {
        let current = Date(timeIntervalSince1970: 4_000_000)
        let projectedPrev = current.addingTimeInterval(-fiveHours)
        let near = projectedPrev.addingTimeInterval(5 * 60)
        let nearer = projectedPrev.addingTimeInterval(-2 * 60)
        let ends = PastWindowsBudgetCard.windowEnds(
            currentResetsAt: current,
            recordedResets: [near, nearer],
            windowCount: 2
        )
        XCTAssertEqual(ends[1], nearer)
    }
}

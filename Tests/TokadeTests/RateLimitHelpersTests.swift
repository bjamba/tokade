@testable import Tokade
import XCTest

/// Auto-reset projection of the 5-hour window. When Claude Code hasn't
/// messaged since the window expired, Tokade advances the `resetsAt`
/// forward in 5h increments. A regression here would show the wrong window
/// boundaries everywhere on the Budget tab.
final class RateLimitHelpersTests: XCTestCase {
    private func snapshot(resetsAt: Date, pct: Double = 50) -> RateLimitSnapshot {
        RateLimitSnapshot(
            fiveHour: RateLimitWindow(usedPercentage: pct, resetsAt: resetsAt),
            sevenDay: nil,
            modelDisplayName: nil,
            modelId: nil,
            sessionId: nil,
            capturedAt: Date()
        )
    }

    func testFreshDataPassesThroughResetsAt() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)  // 1h from now
        let s = snapshot(resetsAt: resetsAt)
        XCTAssertEqual(effectiveFiveHourResetsAt(rateLimits: s, now: now), resetsAt)
        XCTAssertFalse(isFiveHourDataStale(rateLimits: s, now: now))
    }

    func testStaleDataAdvancesOneCycle() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(-3600)  // 1h ago — stale
        let s = snapshot(resetsAt: resetsAt)
        let effective = effectiveFiveHourResetsAt(rateLimits: s, now: now)
        // One full 5h cycle past the stale resetsAt.
        XCTAssertEqual(effective.timeIntervalSinceReferenceDate,
                       resetsAt.addingTimeInterval(5 * 3600).timeIntervalSinceReferenceDate,
                       accuracy: 1)
        XCTAssertTrue(isFiveHourDataStale(rateLimits: s, now: now))
    }

    func testStaleDataAdvancesMultipleCycles() {
        let now = Date()
        // ~12 hours past the server's resetsAt → 3 full 5h cycles passed.
        let resetsAt = now.addingTimeInterval(-12 * 3600)
        let s = snapshot(resetsAt: resetsAt)
        let effective = effectiveFiveHourResetsAt(rateLimits: s, now: now)
        XCTAssertEqual(effective.timeIntervalSinceReferenceDate,
                       resetsAt.addingTimeInterval(3 * 5 * 3600).timeIntervalSinceReferenceDate,
                       accuracy: 1)
    }

    func testNoSnapshotFallsBackToFiveHoursOut() {
        let now = Date()
        let effective = effectiveFiveHourResetsAt(rateLimits: nil, now: now)
        XCTAssertEqual(effective.timeIntervalSinceReferenceDate,
                       now.addingTimeInterval(5 * 3600).timeIntervalSinceReferenceDate,
                       accuracy: 1)
        XCTAssertFalse(isFiveHourDataStale(rateLimits: nil, now: now))
    }
}

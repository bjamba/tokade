import Foundation

/// Watches `UsageStore` for usage milestones a real user wants to know
/// about — rate-limit thresholds crossing and large token bursts — and
/// surfaces them through `Notifier`. Stateful so each milestone fires at
/// most once per relevant window.
///
/// Pure logic; called from `TokadeApp`'s background tick loop alongside
/// the Token Gaiden tick. Skips entirely when the user has disabled the
/// `usageAlerts` setting.
@MainActor
final class UsageAlerter {
    /// Five-hour-window thresholds we fire on (percentages). Sorted so we
    /// can find the highest one a current usage crosses.
    static let fiveHourThresholds: [Int] = [50, 75, 90]

    /// Token count over a 5-minute window that triggers a "big burn"
    /// notification. Tuned so it doesn't fire on routine coding sessions.
    static let burstWindow: TimeInterval = 5 * 60
    static let burstTokens: Int = 500_000
    /// Minimum gap between consecutive burst notifications so a sustained
    /// heavy session doesn't spam the user.
    static let burstCooldown: TimeInterval = 15 * 60

    private weak var notifier: Notifier?

    /// Highest five-hour threshold already announced for the *current*
    /// window. We reset this when usage drops below the next-lower
    /// threshold (i.e., when the window rolls over and percentage falls).
    private var notifiedThreshold: Int = 0
    /// Last time we surfaced a burst notification, for cooldown checks.
    private var lastBurstAt: Date?
    /// Highest grandTotal of the last-5-min window we've reported on.
    /// Tracked so a slow-burning window doesn't refire every poll.
    private var lastBurstReportedTotal: Int = 0

    init(notifier: Notifier?) {
        self.notifier = notifier
    }

    /// Evaluate the latest store snapshot and emit any newly-due alerts.
    /// Called on each background tick.
    func evaluate(events: [UsageEvent], rateLimits: RateLimitSnapshot?) {
        guard let notifier, notifier.usageAlerts else { return }
        if let pct = rateLimits?.fiveHour?.usedPercentage {
            evaluateRateLimit(pct: pct, notifier: notifier)
        }
        evaluateBurst(events: events, notifier: notifier)
    }

    /// Fire on the highest threshold crossed since last notification.
    /// If usage drops back below a previously-fired threshold, the slot
    /// resets so the next crossing notifies again.
    private func evaluateRateLimit(pct: Double, notifier: Notifier) {
        // Threshold crossing — find the highest threshold ≤ current pct
        // that we haven't already announced for this elevated state.
        let highest = Self.fiveHourThresholds.last(where: { Double($0) <= pct }) ?? 0
        if highest > notifiedThreshold {
            notifier.notify(
                title: "⚠️ Claude usage at \(highest)%",
                body: String(format: "%.0f%% of your 5-hour budget consumed.", pct),
                kind: highest >= 90 ? .danger : .warning
            )
            notifiedThreshold = highest
        }
        // Reset path: usage dipped below the next-lower threshold, so the
        // next crossing should fire again. Compares against the threshold
        // immediately below the one we last fired.
        if let below = Self.fiveHourThresholds.last(where: { $0 < notifiedThreshold }),
           pct < Double(below) {
            notifiedThreshold = below
        } else if notifiedThreshold > 0,
                  pct < Double(Self.fiveHourThresholds.first ?? 50) {
            notifiedThreshold = 0
        }
    }

    /// Big-burn detector: sum grandTotal across events in the last
    /// `burstWindow`. If above threshold AND the cooldown has elapsed,
    /// fire. We dedupe by tracking the highest reported total so a slow
    /// build-up over multiple polls only notifies once per cooldown.
    private func evaluateBurst(events: [UsageEvent], notifier: Notifier) {
        let cutoff = Date().addingTimeInterval(-Self.burstWindow)
        let recent = events.filter { $0.timestamp >= cutoff }
        let total = recent.reduce(0) { $0 + $1.grandTotal }
        guard total >= Self.burstTokens else {
            // Window rolled — allow next burst to fire even if cooldown
            // hasn't elapsed yet, by clearing the dedupe baseline.
            lastBurstReportedTotal = 0
            return
        }
        let now = Date()
        if let last = lastBurstAt, now.timeIntervalSince(last) < Self.burstCooldown {
            return
        }
        // Only fire if this window is materially busier than the one we
        // last reported on — prevents notifying twice for the same burst
        // straddling the cooldown boundary.
        if total <= lastBurstReportedTotal { return }
        notifier.notify(
            title: "🔥 Token burst",
            body: "\(formatTokens(total)) consumed in the last 5 min.",
            kind: .warning
        )
        lastBurstAt = now
        lastBurstReportedTotal = total
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1000     { return String(format: "%.0fK", Double(n) / 1000) }
        return "\(n)"
    }
}

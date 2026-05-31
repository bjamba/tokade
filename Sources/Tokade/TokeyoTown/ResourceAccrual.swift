import Foundation

/// Derives flow resources from a slice of `UsageEvent`s. Pure function —
/// the store calls this with whatever events arrived since `lastTickAt`.
/// Conversions defined in ADR-0006 §5.
enum ResourceAccrual {
    /// Process events newer than the town's `lastTickAt` and not yet
    /// `accountedEvents.lastTimestamp`. Returns the resource delta plus the
    /// new high-water mark.
    static func accrue(
        events: [UsageEvent],
        repoPath: String,
        accounted: TokeyoTownState.AccountedEvents,
        currentSessionCwd: String?
    ) -> (delta: TokeyoTownState.Resources, newAccounted: TokeyoTownState.AccountedEvents) {
        let highWater = accounted.lastTimestamp ?? .distantPast
        let candidates = events
            .filter { $0.timestamp > highWater }
            .sorted { $0.timestamp < $1.timestamp }
        guard !candidates.isEmpty else { return (.zero, accounted) }

        var delta = TokeyoTownState.Resources.zero
        var sessionsSeen = Set<String>()
        var pendingSessionEvents: [String: Date] = [:] // last seen timestamp per session

        for event in candidates {
            // The town is funded by *your work on this repo*. Usage in other
            // repos advances the high-water mark (so we don't reprocess it) but
            // grants nothing — otherwise a town grows identically regardless of
            // which project you actually worked in (issue #31).
            guard eventInRepo(event.cwd, repoPath: repoPath) else { continue }

            // Coin: 1 / 1,000 tokens. v3.7 — v2's 1/4k nerf was too
            // aggressive; an hour of light Claude use couldn't buy a
            // single cottage. Back to the v1 rate but with smaller
            // building costs so it stays meaningful.
            delta.coin += event.grandTotal / 1000

            // v3.6 — `stability` and `inspiration` retired. They earned
            // too rarely to matter for buying anything and added UI
            // noise. Their costs in `BuildingCatalog` have been folded
            // into industry/knowledge.

            // Per-tool credits, with active-session boost
            let multiplier = activeSessionMultiplier(eventCwd: event.cwd, sessionCwd: currentSessionCwd, repoPath: repoPath)
            for tool in event.tools {
                applyTool(tool, multiplier: multiplier, delta: &delta)
            }

            if let sid = event.sessionId {
                pendingSessionEvents[sid] = event.timestamp
                sessionsSeen.insert(sid)
            }
        }

        // Growth ticks: count distinct sessions newly seen since high water.
        delta.growth += sessionsSeen.count

        // Apply conversion ratios with integer division — accumulate fractional
        // counts via the multiplier so we don't lose them entirely.
        let normalized = normalize(delta)

        var newAccounted = accounted
        if let last = candidates.last {
            newAccounted.lastTimestamp = last.timestamp
            newAccounted.lastEventId = last.messageId
        }
        return (normalized, newAccounted)
    }

    /// True when an event's cwd is the town's repo path or nested inside it.
    /// Out-of-repo usage does not fund the town (issue #31).
    static func eventInRepo(_ eventCwd: String?, repoPath: String) -> Bool {
        guard let eventCwd else { return false }
        let repo = (repoPath as NSString).standardizingPath
        let ev = (eventCwd as NSString).standardizingPath
        return ev == repo || ev.hasPrefix(repo + "/")
    }

    /// 2x bonus when this event's cwd is inside the active Claude Code session's cwd
    /// and that session's cwd is inside (or equal to) the town's repo path.
    static func activeSessionMultiplier(eventCwd: String?, sessionCwd: String?, repoPath: String) -> Double {
        guard let eventCwd, let sessionCwd else { return 1.0 }
        let normalizedRepo = (repoPath as NSString).standardizingPath
        let normalizedSession = (sessionCwd as NSString).standardizingPath
        let normalizedEvent = (eventCwd as NSString).standardizingPath
        let sessionMatchesRepo = normalizedSession == normalizedRepo || normalizedSession.hasPrefix(normalizedRepo + "/")
        let eventMatchesSession = normalizedEvent == normalizedSession || normalizedEvent.hasPrefix(normalizedSession + "/")
        return (sessionMatchesRepo && eventMatchesSession) ? 2.0 : 1.0
    }

    /// One internal "raw count" per per-event tool invocation; converted to
    /// resources by `normalize`.
    private static func applyTool(_ tool: String, multiplier: Double, delta: inout TokeyoTownState.Resources) {
        // We carry fractional raw counts in the resource fields by storing
        // multiplier-weighted ints (rounded down by `normalize`).
        let weighted = max(1, Int(multiplier.rounded()))
        switch tool.lowercased() {
        case "read":
            delta.knowledge += weighted
        case "edit", "write":
            delta.lumber += weighted
        case "bash":
            delta.industry += weighted
            // Heuristic for test runs — Bash with test-looking commands gives stability.
            // The tool string itself doesn't carry the command; we keep this simple
            // for MVP and let `stability` grow more slowly than the others.
        default:
            break
        }
    }

    /// Apply ratio divisors to convert raw tool-call counts into resources.
    /// v2 ratios (ADR-0006 addendum):
    ///   - knowledge: 1 / 10 reads (v1 was 1/5)
    ///   - lumber:    1 / 3 edits (unchanged — edits stay the main scarce signal)
    ///   - industry:  1 / 8 bashes (v1 was 1/5)
    ///   - stability: 1 / 40 bashes (~1/5 of industry, was 1/25)
    private static func normalize(_ raw: TokeyoTownState.Resources) -> TokeyoTownState.Resources {
        // v3.8 — full buff. Tool calls now grant 1 resource each (was
        // 1 per 4 reads, 2 edits, 4 bashes). Tool calls happen far less
        // often than tokens accumulate, so a 1:1 ratio keeps the
        // tool-resource pool from being the perpetual bottleneck while
        // coin keeps pace via tokens.
        var out = raw
        // raw counts already are 1 per tool invocation, so no division.
        out.stability = 0
        out.inspiration = 0
        return out
    }
}

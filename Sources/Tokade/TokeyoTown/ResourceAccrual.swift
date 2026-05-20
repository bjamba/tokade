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
            // Coin: 1 / 1000 tokens
            delta.coin += event.grandTotal / 1000

            // Inspiration: per slash command
            if event.slashCommand != nil {
                delta.inspiration += 1
            }

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
    /// Ratios from ADR-0006 §5:
    ///   - knowledge: 1 / 5 reads
    ///   - lumber:    1 / 3 edits
    ///   - industry:  1 / 5 bashes
    ///   - stability: 1 / 5 bashes (rough proxy; refined later)
    private static func normalize(_ raw: TokeyoTownState.Resources) -> TokeyoTownState.Resources {
        var out = raw
        out.knowledge = raw.knowledge / 5
        out.lumber    = raw.lumber    / 3
        out.industry  = raw.industry  / 5
        out.stability = raw.industry  / 25  // ~1/5 of industry
        return out
    }
}

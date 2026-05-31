import Foundation

/// Derives flow resources from a slice of `UsageEvent`s. Pure function —
/// the store calls this with whatever events arrived since `lastTickAt`.
///
/// Shipped economy (v3.x — see ADR-0006 "Revision: economy v3.x"):
///   - coin:      `grandTotal / 1000` per in-repo event (no per-token nerf)
///   - knowledge: 1 per `Read` tool call
///   - lumber:    1 per `Edit` / `Write` tool call
///   - industry:  1 per `Bash` tool call
///   - growth:    1 per distinct session seen
///   - stability / inspiration: RETIRED — always zero (see `normalize`)
/// Only events whose `cwd` is in the adopted repo fund the town (issue #31).
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

            // `stability` and `inspiration` are retired (always zero); see
            // `normalize`. Their building costs were folded into
            // industry/knowledge in `BuildingCatalog`.

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

        // Force-zero the retired resources (stability / inspiration). Tool
        // credits are already 1-per-call; there is no division step.
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

    /// Grants one resource per tool invocation (the shipped 1:1 economy),
    /// scaled by the active-session multiplier. `Read`→knowledge,
    /// `Edit`/`Write`→lumber, `Bash`→industry.
    private static func applyTool(_ tool: String, multiplier: Double, delta: inout TokeyoTownState.Resources) {
        // 1 resource per call, weighted by the active-session multiplier
        // (1× normally, 2× when working in the town's repo).
        let weighted = max(1, Int(multiplier.rounded()))
        switch tool.lowercased() {
        case "read":
            delta.knowledge += weighted
        case "edit", "write":
            delta.lumber += weighted
        case "bash":
            delta.industry += weighted
        default:
            break
        }
    }

    /// Force-zeros the retired resources. As of the v3.x economy, tool
    /// calls grant 1 resource each (`applyTool` already does this — there
    /// is no division step), so this only clears `stability` and
    /// `inspiration`, which are retired and never displayed but kept on
    /// the struct for save-file compatibility.
    private static func normalize(_ raw: TokeyoTownState.Resources) -> TokeyoTownState.Resources {
        var out = raw
        // Tool credits are already 1-per-call; no division. Only the
        // retired resources need clamping.
        out.stability = 0
        out.inspiration = 0
        return out
    }
}

import Foundation

/// Pure helpers for per-repo districts (issue #80, Phase 1 — data only).
///
/// A town's districts are the top sub-packages by LOC (from
/// `RepoScanner.detectSubPackages`) plus one synthesized **core** district
/// for everything else. Phase 1 only tracks per-district activity counters
/// from cwd→district mapping; it makes no map/geography change. Phase 2 will
/// consume `District.activityTokens` to grow district geography from seeds.
enum Districts {
    /// The id of the synthesized catch-all district.
    static let coreId = "core"
    /// The display name of the synthesized catch-all district.
    static let coreName = "core"

    /// Build the district list from detected sub-packages.
    ///
    /// Each sub-package becomes a district (id derived from its
    /// `rootSubpath`), and one synthesized **core** district (id "core",
    /// `rootSubpath` "") is appended for the remainder of the repo. A repo
    /// with no sub-packages yields exactly the core district — today's
    /// whole-repo behavior. `originLOC` records each unit's size at scan
    /// time; the core's `originLOC` is the repo total minus the sum of the
    /// sub-package LOCs (clamped at 0).
    static func makeDistricts(
        subPackages: [RepoScanner.SubPackageInfo],
        totalLOC: Int
    ) -> [TokeyoTownState.District] {
        var districts = subPackages.map { sp in
            TokeyoTownState.District(
                id: districtId(forSubpath: sp.rootSubpath),
                name: sp.name,
                rootSubpath: sp.rootSubpath,
                originLOC: sp.loc,
                activityTokens: 0,
                lastActiveAt: nil
            )
        }
        let claimedLOC = subPackages.reduce(0) { $0 + $1.loc }
        let coreLOC = max(0, totalLOC - claimedLOC)
        districts.append(TokeyoTownState.District(
            id: coreId,
            name: coreName,
            rootSubpath: "",
            originLOC: coreLOC,
            activityTokens: 0,
            lastActiveAt: nil
        ))
        return districts
    }

    /// A single whole-repo core district — the lazy default for old saves
    /// (issue #80 migration). `originLOC` is the repo's total LOC.
    static func coreOnly(totalLOC: Int) -> [TokeyoTownState.District] {
        [TokeyoTownState.District(
            id: coreId,
            name: coreName,
            rootSubpath: "",
            originLOC: max(0, totalLOC),
            activityTokens: 0,
            lastActiveAt: nil
        )]
    }

    /// Stable id derived from a sub-package's `rootSubpath`. Empty subpath
    /// (the core) maps to "core".
    static func districtId(forSubpath subpath: String) -> String {
        subpath.isEmpty ? coreId : subpath
    }

    /// Index (into `districts`) of the district owning an event's cwd, by
    /// **longest-prefix match** of the event's repo-relative path against
    /// each district's `rootSubpath`. Ties broken by the longest matching
    /// subpath. Falls back to the core district (`rootSubpath == ""`) when
    /// no sub-package matches. Returns `nil` only when the cwd is not in the
    /// repo or there is no core district to fall back to.
    static func districtIndex(
        eventCwd: String?,
        repoPath: String,
        districts: [TokeyoTownState.District]
    ) -> Int? {
        guard ResourceAccrual.eventInRepo(eventCwd, repoPath: repoPath),
              let eventCwd else { return nil }

        let repo = (repoPath as NSString).standardizingPath
        let ev = (eventCwd as NSString).standardizingPath
        // Repo-relative path of the event cwd (no leading slash).
        let relative: String = if ev == repo {
            ""
        } else if ev.hasPrefix(repo + "/") {
            String(ev.dropFirst(repo.count + 1))
        } else {
            ""
        }

        var bestIndex: Int?
        var bestLength = -1
        var coreIndex: Int?
        for (i, d) in districts.enumerated() {
            if d.rootSubpath.isEmpty {
                coreIndex = i
                continue
            }
            // Match when the event path equals or is nested under the
            // district's subpath.
            if relative == d.rootSubpath || relative.hasPrefix(d.rootSubpath + "/") {
                if d.rootSubpath.count > bestLength {
                    bestLength = d.rootSubpath.count
                    bestIndex = i
                }
            }
        }
        return bestIndex ?? coreIndex
    }

    /// Attribute a tick's in-repo events to their owning districts.
    ///
    /// For each event whose cwd is in the repo (same test
    /// `ResourceAccrual` uses), add `event.grandTotal` to the matched
    /// district's `activityTokens` and set its `lastActiveAt = now`.
    /// Out-of-repo events are ignored. Mutates `districts` in place.
    static func applyActivity(
        _ districts: inout [TokeyoTownState.District],
        events: [UsageEvent],
        repoPath: String,
        now: Date
    ) {
        for event in events {
            guard let idx = districtIndex(
                eventCwd: event.cwd,
                repoPath: repoPath,
                districts: districts
            ) else { continue }
            districts[idx].activityTokens += event.grandTotal
            districts[idx].lastActiveAt = now
        }
    }
}

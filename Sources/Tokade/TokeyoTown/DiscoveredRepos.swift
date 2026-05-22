import Foundation

/// Derives the list of repo roots the user has worked in, from the
/// `UsageEvent` stream's `cwd` field. Reuses `Region.projectRoot` so the
/// "what counts as a repo" logic stays consistent with Token Gaiden.
enum DiscoveredRepos {
    struct Entry: Hashable, Identifiable {
        var id: String { path }
        let path: String
        let displayName: String
    }

    /// Unique repo roots, alphabetized by display name. Falls back to the
    /// raw cwd when no project marker is found in any ancestor.
    static func from(events: [UsageEvent]) -> [Entry] {
        var seen = Set<String>()
        var entries: [Entry] = []
        for e in events {
            guard let cwd = e.cwd, !cwd.isEmpty else { continue }
            let root = Region.projectRoot(for: cwd) ?? cwd
            guard seen.insert(root).inserted else { continue }
            entries.append(Entry(
                path: root,
                displayName: URL(fileURLWithPath: root).lastPathComponent
            ))
        }
        return entries.sorted {
            // Alphabetical by display name, then path as tiebreaker.
            if $0.displayName.lowercased() == $1.displayName.lowercased() {
                return $0.path < $1.path
            }
            return $0.displayName.lowercased() < $1.displayName.lowercased()
        }
    }

    /// Substring filter on the path (case-insensitive). Empty query →
    /// the original list unchanged.
    static func filter(_ entries: [Entry], query: String) -> [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        let lower = q.lowercased()
        return entries.filter { $0.path.lowercased().contains(lower) }
    }
}

import Foundation

/// Functions that translate a Claude Code cwd into a region identifier and a
/// region "flavor" seed.
///
/// Region identifiers are the path of the project root relative to the user's
/// home directory (e.g. `code/tokade`). Same path = same region; matching is
/// by cwd prefix, so subdirectories share the parent's region.
enum Region {
    /// File names whose presence in a directory means "this is a project
    /// root." When walking up from a cwd, the first ancestor containing any
    /// of these becomes the region for that cwd — so working in
    /// `code/foo/Sources/Tests/` doesn't spawn a new region per subfolder.
    static let projectMarkers: [String] = [
        ".git", "Package.swift", "Cargo.toml", "package.json",
        "pyproject.toml", "go.mod", "setup.py", "requirements.txt",
        "Gemfile", "pom.xml", "build.gradle", "build.gradle.kts",
        "CMakeLists.txt", "Makefile", ".tokade-region",
    ]

    /// Convert an absolute cwd to a stable region identifier.
    ///
    /// Walks UP from `cwd` until it finds a directory containing one of
    /// `projectMarkers` and uses that as the region root — collapsing
    /// subfolders of the same project to a single region. Falls back to
    /// the cwd itself when no marker is found.
    ///
    /// Strips a leading `$HOME/` if present so the identifier is portable
    /// across machines for the same user. Absolute paths outside the home
    /// directory get their final two path components as the identifier.
    static func identifier(for cwd: String) -> String {
        let trimmed = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        let root = projectRoot(for: trimmed) ?? trimmed
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if root.hasPrefix(home + "/") {
            return String(root.dropFirst(home.count + 1))
        }
        if root == home { return "home" }
        let parts = root.split(separator: "/")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: "/")
        }
        return root
    }

    /// Walk up from `cwd` until a directory containing any `projectMarkers`
    /// is found. Bounded to ~8 levels so misconfigured/test paths don't
    /// scan the whole tree.
    private static func projectRoot(for cwd: String) -> String? {
        let fm = FileManager.default
        var path = cwd
        for _ in 0..<8 {
            for marker in projectMarkers {
                if fm.fileExists(atPath: "\(path)/\(marker)") {
                    return path
                }
            }
            let parent = (path as NSString).deletingLastPathComponent
            if parent == path || parent.isEmpty || parent == "/" { return nil }
            path = parent
        }
        return nil
    }

    /// Pick a region "flavor" from the project files at `cwd`. Used for the
    /// language-themed naming (Stonework Town, Iron Fortress, etc.) per
    /// `docs/02-design/TOKADE_TAB.md` Layer 3.
    ///
    /// Looks for the common marker files. Returns `.wilderness` for unknown
    /// projects. Pure side-effect-free filesystem read.
    static func flavor(for cwd: String) -> Flavor {
        let trimmed = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        // Use the project root so a subfolder inherits the project's flavor.
        let root = projectRoot(for: trimmed) ?? trimmed
        let f = FileManager.default
        func has(_ name: String) -> Bool {
            f.fileExists(atPath: "\(root)/\(name)")
        }
        if has("Package.swift") || has("Tokade.xcodeproj") { return .stonework }
        if has("Cargo.toml") { return .ironFortress }
        if has("pyproject.toml") || has("requirements.txt") || has("setup.py") { return .gardenVillage }
        if has("package.json") { return .bazaar }
        if has("go.mod") { return .openSteppe }
        return .wilderness
    }

    /// LoC-step discovery thresholds. Calibrated so a typical session opens
    /// the village + trainer quickly — players should be talking to NPCs
    /// after 10–20 minutes of real Claude usage, not days.
    enum Discovery: Int, CaseIterable, Codable, Comparable {
        case openRoad   = 0       // entering the region; merchant available
        case village    = 50      // trainer + quests unlock
        case sideTrails = 300     // reserved for future side content
        case dungeon    = 1000    // dungeon "boss" tile unlocks
        case hiddenZone = 5000    // mythic content (future)

        static func < (lhs: Discovery, rhs: Discovery) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var label: String {
            switch self {
            case .openRoad:    return "Open Road"
            case .village:     return "Village"
            case .sideTrails:  return "Side Trails"
            case .dungeon:     return "Dungeon"
            case .hiddenZone:  return "Hidden Zone"
            }
        }

        /// All thresholds that the given step count has unlocked, highest first.
        static func unlocked(forSteps steps: Int) -> [Discovery] {
            allCases.filter { steps >= $0.rawValue }.sorted(by: >)
        }

        /// The next un-reached threshold above `steps`, or nil if all unlocked.
        static func next(forSteps steps: Int) -> Discovery? {
            allCases.filter { steps < $0.rawValue }.sorted(by: <).first
        }
    }

    /// Weighted "step" for one event. LoC isn't directly tracked yet so we
    /// approximate via tool-call count + token output.
    static func stepsForEvent(_ e: UsageEvent) -> Int {
        let tools = e.tools.count
        let outputContribution = e.outputTokens / 200
        return tools * 2 + outputContribution + 1   // +1 baseline per message
    }

    /// Deterministic pseudo-random 2D position in `[0, 1]^2` for a region.
    /// Hash-based so a region's spot on the map is stable across launches
    /// without needing to persist a separate seed. The hash uses a 32-bit
    /// FNV-1a so the result is identical across machines.
    static func position(for region: String) -> (x: Double, y: Double) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in region.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01B3
        }
        // Split hash into two coordinates and bring them into [0.07, 0.93]
        // so points don't smash against the canvas border.
        let xRaw = Double((hash >> 32) & 0xFFFF_FFFF) / Double(UInt32.max)
        let yRaw = Double(hash & 0xFFFF_FFFF) / Double(UInt32.max)
        return (0.07 + xRaw * 0.86, 0.07 + yRaw * 0.86)
    }

    enum Flavor: String, Codable, CaseIterable {
        case stonework      // Swift / Xcode
        case ironFortress   // Rust
        case gardenVillage  // Python
        case bazaar         // JS/TS
        case openSteppe     // Go
        case wilderness     // unrecognized

        /// Player-visible name shown in the region card.
        var displayName: String {
            switch self {
            case .stonework:     return "Stonework Town"
            case .ironFortress:  return "Iron Fortress"
            case .gardenVillage: return "Garden Village"
            case .bazaar:        return "Bazaar"
            case .openSteppe:    return "Open Steppe"
            case .wilderness:    return "Wilderness"
            }
        }
    }
}

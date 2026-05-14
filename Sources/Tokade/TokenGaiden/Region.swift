import Foundation

/// Functions that translate a Claude Code cwd into a region identifier and a
/// region "flavor" seed.
///
/// Region identifiers are the path of the project root relative to the user's
/// home directory (e.g. `code/tokade`). Same path = same region; matching is
/// by cwd prefix, so subdirectories share the parent's region.
enum Region {
    /// Convert an absolute cwd to a stable region identifier.
    ///
    /// Strips a leading `$HOME/` if present so the identifier is portable
    /// across machines for the same user. Absolute paths outside the home
    /// directory get their final two path components as the identifier.
    static func identifier(for cwd: String) -> String {
        let trimmed = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if trimmed.hasPrefix(home + "/") {
            return String(trimmed.dropFirst(home.count + 1))
        }
        if trimmed == home { return "home" }
        // Outside home — collapse to the last two path components for a stable
        // identifier without leaking the absolute filesystem location.
        let parts = trimmed.split(separator: "/")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: "/")
        }
        return trimmed
    }

    /// Pick a region "flavor" from the project files at `cwd`. Used for the
    /// language-themed naming (Stonework Town, Iron Fortress, etc.) per
    /// `docs/02-design/TOKADE_TAB.md` Layer 3.
    ///
    /// Looks for the common marker files. Returns `.wilderness` for unknown
    /// projects. Pure side-effect-free filesystem read.
    static func flavor(for cwd: String) -> Flavor {
        let f = FileManager.default
        func has(_ name: String) -> Bool {
            f.fileExists(atPath: "\(cwd)/\(name)")
        }
        if has("Package.swift") || has("Tokade.xcodeproj") || has("Cargo.toml.swift") { return .stonework }
        if has("Cargo.toml") { return .ironFortress }
        if has("pyproject.toml") || has("requirements.txt") || has("setup.py") { return .gardenVillage }
        if has("package.json") { return .bazaar }
        if has("go.mod") { return .openSteppe }
        return .wilderness
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

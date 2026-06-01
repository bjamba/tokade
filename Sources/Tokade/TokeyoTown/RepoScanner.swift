import CryptoKit
import Foundation
import os.log

/// Reads metadata from a local folder to derive a town's terrain & unlocks.
/// 100% local — no network, no Claude. Enforced by the existing "no network
/// code" guardrail (see `scripts/check.sh` and CLAUDE.md § No network code).
enum RepoScanner {
    private static let log = Logger(subsystem: "com.bjamba.tokade", category: "RepoScanner")

    /// Source-file extensions we count toward LOC + primary-language detection.
    /// Keep this in sync with the biome mapping in `Self.biome(forLanguage:)`.
    static let sourceExtensions: [String: String] = [
        // Swift
        "swift": "swift",
        // Rust / C-family
        "rs": "rust", "c": "c", "h": "c", "cpp": "cpp", "cc": "cpp", "hpp": "cpp", "zig": "zig",
        // Python-family
        "py": "python", "rb": "ruby", "r": "r",
        // JS-family
        "js": "javascript", "mjs": "javascript", "ts": "typescript", "tsx": "typescript",
        "jsx": "javascript", "html": "html", "css": "css", "scss": "css",
        // Static / typed
        "go": "go", "java": "java", "cs": "csharp", "php": "php",
        // Mobile
        "kt": "kotlin", "dart": "dart",
        // Docs (counted toward LOC but not primary lang)
        "md": "markdown"
    ]

    /// Max files we'll walk during a scan. Keeps scans snappy on huge repos.
    static let fileWalkCap = 5000
    static let maxDepth = 8

    enum ScanError: Error {
        case notADirectory(URL)
        case empty(URL)
    }

    struct ScanResult {
        let path: URL
        let displayName: String
        let primaryLanguage: String
        let biome: TokeyoTownState.Biome
        let era: TokeyoTownState.Era
        let ageInDays: Int
        let loc: Int
        let contributorCount: Int
        let lushness: Double
        let mapSize: Int
        /// v3.5 — soft hints that drive the pre-seed step at town
        /// creation. True if the repo has the kind of artifact each
        /// signals (a tests dir, a docs dir, etc.).
        var hasTestsDir: Bool = false
        var hasDocsDir: Bool = false
        var hasReadme: Bool = false
        var hasCi: Bool = false
        var fileCount: Int = 0
    }

    /// Run a fresh scan of `url`. Throws if the path isn't a directory.
    static func scan(_ url: URL) throws -> ScanResult {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw ScanError.notADirectory(url)
        }

        let locByLang = countLOC(at: url)
        let totalLOC = locByLang.values.reduce(0, +)
        let primaryLang = locByLang
            .filter { $0.key != "markdown" }
            .max(by: { $0.value < $1.value })?
            .key ?? "unknown"

        let (firstCommit, commitsLast30) = gitStats(at: url)
        let contributors = gitContributorCount(at: url)

        let ageInDays: Int = if let first = firstCommit {
            max(0, Int(Date.now.timeIntervalSince(first) / 86400))
        } else {
            0
        }

        let fm = FileManager.default
        let testsDir = ["tests", "test", "Tests", "spec", "__tests__"]
            .contains { fm.fileExists(atPath: url.appendingPathComponent($0).path) }
        let docsDir = ["docs", "doc", "documentation"]
            .contains { fm.fileExists(atPath: url.appendingPathComponent($0).path) }
        let readme = ["README.md", "README.rst", "README", "readme.md"]
            .contains { fm.fileExists(atPath: url.appendingPathComponent($0).path) }
        let ci = [".github/workflows", ".gitlab-ci.yml", "circle.yml", ".circleci"]
            .contains { fm.fileExists(atPath: url.appendingPathComponent($0).path) }

        return ScanResult(
            path: url,
            displayName: url.lastPathComponent,
            primaryLanguage: primaryLang,
            biome: biome(forLanguage: primaryLang),
            era: era(forAgeInDays: ageInDays),
            ageInDays: ageInDays,
            loc: totalLOC,
            contributorCount: max(1, contributors),
            lushness: lushness(forCommitsLast30: commitsLast30),
            mapSize: mapSize(forLOC: totalLOC),
            hasTestsDir: testsDir,
            hasDocsDir: docsDir,
            hasReadme: readme,
            hasCi: ci,
            fileCount: 0
        )
    }

    // MARK: - Sub-package detection (issue #80, Phase 1)

    /// A detected sub-package within a repo: a meaningful unit (a
    /// manifest-anchored package, or — when a repo has no manifests — a
    /// top-level source dir) that can become a district. `rootSubpath` is
    /// relative to the scanned repo root. Local-only by construction (no
    /// network); detection just walks the same tree `scan` does.
    struct SubPackageInfo: Equatable {
        let name: String
        /// Path relative to the repo root (e.g. "packages/api").
        let rootSubpath: String
        let loc: Int
    }

    /// Manifest filenames that anchor a sub-package. A subdirectory
    /// containing any of these is treated as its own package.
    static let packageManifestNames: Set<String> = [
        "Package.swift", "package.json", "pyproject.toml",
        "go.mod", "Cargo.toml", "build.gradle", "build.gradle.kts"
    ]

    /// Top-level source directories used as the fallback unit when a repo
    /// has no nested manifests. `packages/*` and `services/*` expand to
    /// their immediate children; the others are taken whole.
    static let fallbackSourceDirs = ["packages", "services", "src", "app", "lib"]

    /// Dirs skipped during any walk (same set `countLOC` skips).
    private static let skipDirNames: Set<String> = [
        "node_modules", ".build", "build", "dist", "target", ".git",
        "DerivedData", "Pods", ".venv", "venv", "__pycache__"
    ]

    /// Detect a repo's sub-packages, most-LOC first, capped at `max`.
    ///
    /// Manifest-anchored first: any subdir (below the root) that contains
    /// its own package manifest. When the repo has no nested manifests, fall
    /// back to top-level source dirs (`packages/*`, `services/*`, `src`,
    /// `app`, `lib`) ranked by LOC. Returns `[]` for a single-package repo
    /// (no nested manifests, no recognised source dirs) — the caller
    /// synthesizes the lone "core" district in that case.
    ///
    /// 100% local — only reads the local filesystem (same file-walk caps,
    /// skip list, and LOC counter as `scan`). No network, no Claude.
    static func detectSubPackages(root: URL, max: Int = 5) -> [SubPackageInfo] {
        let anchored = manifestAnchoredSubPackages(root: root)
        let candidates = anchored.isEmpty ? fallbackSubPackages(root: root) : anchored
        // Sort by LOC desc, tie-broken by rootSubpath asc for determinism.
        return Array(
            candidates
                .sorted {
                    $0.loc != $1.loc ? $0.loc > $1.loc : $0.rootSubpath < $1.rootSubpath
                }
                .prefix(max)
        )
    }

    /// Walk the tree (respecting the same depth/file caps and skip list as
    /// `countLOC`) collecting every directory below the root that holds one
    /// of `packageManifestNames`. The root itself is excluded (its manifest
    /// describes the whole repo, not a sub-package).
    private static func manifestAnchoredSubPackages(root: URL) -> [SubPackageInfo] {
        let rootPath = root.standardizedFileURL.path
        var found: [URL] = []
        var walked = 0

        func walk(_ dir: URL, depth: Int) {
            guard depth <= maxDepth, walked < fileWalkCap else { return }
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            // Does *this* dir hold a manifest? (Skip the root itself.)
            if dir.standardizedFileURL.path != rootPath,
               contents.contains(where: { packageManifestNames.contains($0.lastPathComponent) }) {
                found.append(dir)
            }
            for item in contents {
                if walked >= fileWalkCap { return }
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir else {
                    walked += 1
                    continue
                }
                if skipDirNames.contains(item.lastPathComponent) { continue }
                walk(item, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        return found.map { dir in
            SubPackageInfo(
                name: dir.lastPathComponent,
                rootSubpath: relativeSubpath(of: dir, under: rootPath),
                loc: locUnder(dir)
            )
        }
    }

    /// Fallback: top-level source dirs by LOC. `packages/` and `services/`
    /// expand to their immediate child dirs (the conventional monorepo
    /// layout); `src`, `app`, `lib` are taken whole if present.
    private static func fallbackSubPackages(root: URL) -> [SubPackageInfo] {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        var result: [SubPackageInfo] = []

        for name in fallbackSourceDirs {
            let dir = root.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            if name == "packages" || name == "services" {
                let children = (try? fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                for child in children {
                    let childIsDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    guard childIsDir, !skipDirNames.contains(child.lastPathComponent) else { continue }
                    result.append(SubPackageInfo(
                        name: child.lastPathComponent,
                        rootSubpath: relativeSubpath(of: child, under: rootPath),
                        loc: locUnder(child)
                    ))
                }
            } else {
                result.append(SubPackageInfo(
                    name: name,
                    rootSubpath: relativeSubpath(of: dir, under: rootPath),
                    loc: locUnder(dir)
                ))
            }
        }
        return result
    }

    /// Path of `url` relative to `rootPath` (no leading slash). "" if equal.
    private static func relativeSubpath(of url: URL, under rootPath: String) -> String {
        let p = url.standardizedFileURL.path
        guard p.hasPrefix(rootPath + "/") else { return p == rootPath ? "" : p }
        return String(p.dropFirst(rootPath.count + 1))
    }

    /// Total source LOC under a directory, summed across languages, using
    /// the same counter + caps as `scan`.
    private static func locUnder(_ dir: URL) -> Int {
        countLOC(at: dir).values.reduce(0, +)
    }

    /// SHA-256 of the resolved path, first 16 hex chars. Stable townId.
    static func townId(for path: URL) -> String {
        let resolved = path.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(resolved.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Mapping

    static func biome(forLanguage lang: String) -> TokeyoTownState.Biome {
        switch lang {
        case "swift", "kotlin", "dart":
            return .beach
        case "rust", "c", "cpp", "zig":
            return .tundra
        case "python", "ruby", "r":
            return .forest
        case "javascript", "typescript", "html", "css":
            return .plain
        case "go", "java", "csharp", "php":
            return .desert
        default:
            return .plain
        }
    }

    static func era(forAgeInDays days: Int) -> TokeyoTownState.Era {
        if days < 90 { return .modern }
        if days < 730 { return .contemporary }
        return .classical
    }

    static func mapSize(forLOC loc: Int) -> Int {
        // v2 — lower floor (12) so a tiny repo's town isn't dominated by
        // empty tiles when the renderer zooms in.
        let raw = Int(Double(max(0, loc) / 100).squareRoot())
        return min(48, max(12, raw))
    }

    static func lushness(forCommitsLast30 commits: Int) -> Double {
        // 0 commits → 0.10 (autumnal, not dead), 30+ commits → 1.00
        let n = Double(min(commits, 30)) / 30.0
        return 0.10 + 0.90 * n
    }

    // MARK: - LOC

    private static func countLOC(at root: URL) -> [String: Int] {
        var totals: [String: Int] = [:]
        var walked = 0

        func walk(_ dir: URL, depth: Int) {
            guard depth <= maxDepth, walked < fileWalkCap else { return }
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for item in contents {
                if walked >= fileWalkCap { return }
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir {
                    // Skip common non-source dirs to keep scans snappy.
                    let name = item.lastPathComponent
                    if ["node_modules", ".build", "build", "dist", "target", ".git",
                        "DerivedData", "Pods", ".venv", "venv", "__pycache__"].contains(name) { continue }
                    walk(item, depth: depth + 1)
                } else {
                    walked += 1
                    let ext = item.pathExtension.lowercased()
                    guard let lang = sourceExtensions[ext] else { continue }
                    if let lines = countLines(in: item) {
                        totals[lang, default: 0] += lines
                    }
                }
            }
        }

        walk(root, depth: 0)
        return totals
    }

    private static func countLines(in url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Cap individual files at ~1 MB to keep wild generated files from dominating.
        if data.count > 1_000_000 { return nil }
        var n = 0
        for byte in data where byte == 0x0A { n += 1 }
        return n
    }

    // MARK: - git

    /// (firstCommitDate, commitsInLast30Days) — both nil/0 if not a git repo.
    private static func gitStats(at root: URL) -> (Date?, Int) {
        guard isGitRepo(at: root) else { return (nil, 0) }
        let firstISO = runGit(["log", "--reverse", "--format=%aI", "--max-count=1"], at: root) ?? ""
        let first = ISO8601DateFormatter().date(from: firstISO.trimmingCharacters(in: .whitespacesAndNewlines))

        let since = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-30 * 86400))
        let recent = runGit(["log", "--since=\(since)", "--format=%H"], at: root) ?? ""
        let count = recent.split(separator: "\n").count
        return (first, count)
    }

    private static func gitContributorCount(at root: URL) -> Int {
        guard isGitRepo(at: root) else { return 0 }
        let out = runGit(["shortlog", "-sn", "HEAD"], at: root) ?? ""
        return out.split(separator: "\n").count
    }

    private static func isGitRepo(at root: URL) -> Bool {
        let gitDir = root.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDir)
    }

    private static func runGit(_ args: [String], at root: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            log.warning("git \(args.joined(separator: " "), privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

@testable import Tokade
import XCTest

/// Per-repo districts — Phase 1 (data only). Issue #80.
final class TokeyoTownDistrictsTests: XCTestCase {
    // MARK: - Helpers

    /// Make a temp directory; auto-removed at teardown.
    private var tempDirs: [URL] = []

    override func tearDownWithError() throws {
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs.removeAll()
    }

    private func makeTempRepo() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("districts-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempDirs.append(url)
        return url
    }

    /// Write a Swift file with `lines` newline-terminated lines under `dir`
    /// (creating intermediate dirs), so the LOC counter sees `lines` lines.
    private func writeSource(lines: Int, at relativePath: String, under root: URL) throws {
        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let content = String(repeating: "let x = 1\n", count: lines)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func writeManifest(_ name: String, inDir relativeDir: String, under root: URL) throws {
        let dirURL = root.appendingPathComponent(relativeDir)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        try "".write(to: dirURL.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func makeEvent(
        ts: Date = Date(),
        tokens: Int,
        cwd: String?
    ) -> UsageEvent {
        UsageEvent(
            timestamp: ts,
            model: "claude-opus-4-7",
            inputTokens: tokens,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            outputTokens: 0,
            sessionId: "s1",
            messageId: UUID().uuidString,
            cwd: cwd,
            tools: [],
            slashCommand: nil
        )
    }

    // MARK: - Detection: manifest-anchored

    func testDetectSubPackagesPicksUpManifestDirs() throws {
        let root = try makeTempRepo()
        // Two manifest-anchored sub-packages + some root-level source.
        try writeManifest("Package.swift", inDir: "packages/api", under: root)
        try writeSource(lines: 30, at: "packages/api/Sources/api.swift", under: root)
        try writeManifest("package.json", inDir: "packages/web", under: root)
        try writeSource(lines: 10, at: "packages/web/src/index.ts", under: root)
        // A root-level manifest should NOT itself become a sub-package.
        try writeManifest("Package.swift", inDir: ".", under: root)

        let subs = RepoScanner.detectSubPackages(root: root)
        let names = subs.map(\.name)
        XCTAssertTrue(names.contains("api"))
        XCTAssertTrue(names.contains("web"))
        // Root dir name must not appear as a sub-package.
        XCTAssertFalse(names.contains(root.lastPathComponent))
        // Sorted by LOC desc → api (30) before web (10).
        XCTAssertEqual(subs.first?.name, "api")
        XCTAssertEqual(subs.first?.rootSubpath, "packages/api")
    }

    // MARK: - Detection: fallback to source dirs

    func testDetectSubPackagesFallsBackToSourceDirs() throws {
        let root = try makeTempRepo()
        // No manifests anywhere → fall back to top-level source dirs.
        try writeSource(lines: 50, at: "src/main.swift", under: root)
        try writeSource(lines: 20, at: "app/App.swift", under: root)

        let subs = RepoScanner.detectSubPackages(root: root)
        let names = subs.map(\.name)
        XCTAssertTrue(names.contains("src"))
        XCTAssertTrue(names.contains("app"))
        // src (50) outranks app (20).
        XCTAssertEqual(subs.first?.name, "src")
    }

    func testDetectSubPackagesEmptyForSinglePackageRepo() throws {
        let root = try makeTempRepo()
        // A lone root manifest + flat source, no nested manifests/source dirs.
        try writeManifest("Package.swift", inDir: ".", under: root)
        try writeSource(lines: 10, at: "main.swift", under: root)

        let subs = RepoScanner.detectSubPackages(root: root)
        XCTAssertTrue(subs.isEmpty, "single-package repo yields no sub-packages")
    }

    func testDetectSubPackagesCapsAtFive() throws {
        let root = try makeTempRepo()
        // Seven manifest-anchored sub-packages, descending LOC.
        for i in 0..<7 {
            let dir = "packages/p\(i)"
            try writeManifest("Package.swift", inDir: dir, under: root)
            try writeSource(lines: (7 - i) * 10, at: "\(dir)/Sources/file.swift", under: root)
        }
        let subs = RepoScanner.detectSubPackages(root: root, max: 5)
        XCTAssertEqual(subs.count, 5)
        // Top 5 by LOC are p0 (70) … p4 (30); p5/p6 dropped.
        XCTAssertEqual(subs.map(\.name), ["p0", "p1", "p2", "p3", "p4"])
    }

    // MARK: - makeDistricts

    func testMakeDistrictsTopPlusCore() {
        let subs = [
            RepoScanner.SubPackageInfo(name: "api", rootSubpath: "packages/api", loc: 100),
            RepoScanner.SubPackageInfo(name: "web", rootSubpath: "packages/web", loc: 60)
        ]
        let districts = Districts.makeDistricts(subPackages: subs, totalLOC: 200)
        XCTAssertEqual(districts.count, 3)
        // Sub-packages first, then the synthesized core.
        XCTAssertEqual(districts[0].rootSubpath, "packages/api")
        XCTAssertEqual(districts[0].id, "packages/api")
        XCTAssertEqual(districts[1].rootSubpath, "packages/web")
        let core = districts.last
        XCTAssertEqual(core?.id, "core")
        XCTAssertEqual(core?.rootSubpath, "")
        // Core LOC = total - claimed = 200 - 160 = 40.
        XCTAssertEqual(core?.originLOC, 40)
        // All start with zero activity.
        XCTAssertTrue(districts.allSatisfy { $0.activityTokens == 0 && $0.lastActiveAt == nil })
    }

    func testMakeDistrictsSinglePackageIsCoreOnly() {
        let districts = Districts.makeDistricts(subPackages: [], totalLOC: 120)
        XCTAssertEqual(districts.count, 1)
        XCTAssertEqual(districts[0].id, "core")
        XCTAssertEqual(districts[0].rootSubpath, "")
        XCTAssertEqual(districts[0].originLOC, 120)
    }

    // MARK: - districtIndex

    private func sampleDistricts() -> [TokeyoTownState.District] {
        Districts.makeDistricts(subPackages: [
            RepoScanner.SubPackageInfo(name: "api", rootSubpath: "packages/api", loc: 100),
            RepoScanner.SubPackageInfo(name: "api-core", rootSubpath: "packages/api/core", loc: 40)
        ], totalLOC: 200)
    }

    func testDistrictIndexNestedCwdMatchesSubPackage() throws {
        let districts = Districts.makeDistricts(subPackages: [
            RepoScanner.SubPackageInfo(name: "web", rootSubpath: "packages/web", loc: 50)
        ], totalLOC: 100)
        let idx = Districts.districtIndex(
            eventCwd: "/repo/packages/web/src",
            repoPath: "/repo",
            districts: districts
        )
        XCTAssertNotNil(idx)
        // The web sub-package, not core.
        XCTAssertEqual(try districts[XCTUnwrap(idx)].rootSubpath, "packages/web")
    }

    func testDistrictIndexLongestPrefixWins() throws {
        let districts = sampleDistricts()
        // cwd nested under the deeper "packages/api/core" must beat
        // "packages/api".
        let idx = Districts.districtIndex(
            eventCwd: "/repo/packages/api/core/Sources",
            repoPath: "/repo",
            districts: districts
        )
        XCTAssertNotNil(idx)
        XCTAssertEqual(try districts[XCTUnwrap(idx)].rootSubpath, "packages/api/core")
    }

    func testDistrictIndexUnrelatedInRepoCwdFallsBackToCore() throws {
        let districts = sampleDistricts()
        let idx = Districts.districtIndex(
            eventCwd: "/repo/docs",
            repoPath: "/repo",
            districts: districts
        )
        XCTAssertNotNil(idx)
        XCTAssertEqual(try districts[XCTUnwrap(idx)].id, "core")
    }

    func testDistrictIndexRepoRootFallsBackToCore() throws {
        let districts = sampleDistricts()
        let idx = Districts.districtIndex(
            eventCwd: "/repo",
            repoPath: "/repo",
            districts: districts
        )
        XCTAssertEqual(try districts[XCTUnwrap(idx)].id, "core")
    }

    func testDistrictIndexOutOfRepoIsNil() {
        let districts = sampleDistricts()
        XCTAssertNil(Districts.districtIndex(
            eventCwd: "/other/place",
            repoPath: "/repo",
            districts: districts
        ))
        XCTAssertNil(Districts.districtIndex(
            eventCwd: nil,
            repoPath: "/repo",
            districts: districts
        ))
    }

    // MARK: - applyActivity

    func testApplyActivityIncrementsRightDistrict() throws {
        var districts = sampleDistricts()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let events = [
            makeEvent(tokens: 500, cwd: "/repo/packages/api/Sources"),
            makeEvent(tokens: 200, cwd: "/repo/packages/api/core"),
            makeEvent(tokens: 50, cwd: "/repo/docs") // → core
        ]
        Districts.applyActivity(&districts, events: events, repoPath: "/repo", now: now)

        let api = try XCTUnwrap(districts.first { $0.rootSubpath == "packages/api" })
        let apiCore = try XCTUnwrap(districts.first { $0.rootSubpath == "packages/api/core" })
        let core = try XCTUnwrap(districts.first { $0.id == "core" })
        XCTAssertEqual(api.activityTokens, 500)
        XCTAssertEqual(apiCore.activityTokens, 200)
        XCTAssertEqual(core.activityTokens, 50)
        XCTAssertEqual(api.lastActiveAt, now)
        XCTAssertEqual(apiCore.lastActiveAt, now)
        XCTAssertEqual(core.lastActiveAt, now)
    }

    func testApplyActivityIgnoresOutOfRepoEvents() {
        var districts = sampleDistricts()
        let now = Date()
        let events = [makeEvent(tokens: 9999, cwd: "/somewhere/else")]
        Districts.applyActivity(&districts, events: events, repoPath: "/repo", now: now)
        XCTAssertTrue(districts.allSatisfy { $0.activityTokens == 0 && $0.lastActiveAt == nil })
    }

    // MARK: - Lazy default (old saves)

    func testLazyDefaultCreatesCoreDistrict() throws {
        // An old save decodes districts as nil; coreOnly synthesizes one
        // whole-repo core district so activity still tracks.
        var districts: [TokeyoTownState.District]? = nil
        if districts == nil {
            districts = Districts.coreOnly(totalLOC: 333)
        }
        XCTAssertEqual(districts?.count, 1)
        XCTAssertEqual(districts?.first?.id, "core")
        XCTAssertEqual(districts?.first?.rootSubpath, "")
        XCTAssertEqual(districts?.first?.originLOC, 333)

        // And activity still attributes to it.
        var d = try XCTUnwrap(districts)
        Districts.applyActivity(
            &d,
            events: [makeEvent(tokens: 100, cwd: "/repo/anywhere")],
            repoPath: "/repo",
            now: Date()
        )
        XCTAssertEqual(d[0].activityTokens, 100)
    }
}

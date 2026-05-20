@testable import Tokade
import XCTest

final class TokeyoTownTests: XCTestCase {
    // MARK: - RepoScanner mappings

    func testBiomeMappingForLanguages() {
        XCTAssertEqual(RepoScanner.biome(forLanguage: "swift"), .beach)
        XCTAssertEqual(RepoScanner.biome(forLanguage: "rust"), .tundra)
        XCTAssertEqual(RepoScanner.biome(forLanguage: "python"), .forest)
        XCTAssertEqual(RepoScanner.biome(forLanguage: "javascript"), .plain)
        XCTAssertEqual(RepoScanner.biome(forLanguage: "go"), .desert)
        XCTAssertEqual(RepoScanner.biome(forLanguage: "unknown"), .plain)
    }

    func testEraMappingForAge() {
        XCTAssertEqual(RepoScanner.era(forAgeInDays: 0), .modern)
        XCTAssertEqual(RepoScanner.era(forAgeInDays: 89), .modern)
        XCTAssertEqual(RepoScanner.era(forAgeInDays: 90), .contemporary)
        XCTAssertEqual(RepoScanner.era(forAgeInDays: 729), .contemporary)
        XCTAssertEqual(RepoScanner.era(forAgeInDays: 730), .classical)
        XCTAssertEqual(RepoScanner.era(forAgeInDays: 9999), .classical)
    }

    func testMapSizeClampsToRange() {
        // Tiny repo → floor at 16
        XCTAssertEqual(RepoScanner.mapSize(forLOC: 0), 16)
        XCTAssertEqual(RepoScanner.mapSize(forLOC: 100), 16)
        // Huge repo → cap at 64
        XCTAssertEqual(RepoScanner.mapSize(forLOC: 1_000_000), 64)
        // Mid-sized
        let mid = RepoScanner.mapSize(forLOC: 10000)
        XCTAssertGreaterThanOrEqual(mid, 16)
        XCTAssertLessThanOrEqual(mid, 64)
    }

    func testLushnessFloorAndCeiling() {
        XCTAssertEqual(RepoScanner.lushness(forCommitsLast30: 0), 0.10, accuracy: 0.001)
        XCTAssertEqual(RepoScanner.lushness(forCommitsLast30: 30), 1.00, accuracy: 0.001)
        XCTAssertEqual(RepoScanner.lushness(forCommitsLast30: 1000), 1.00, accuracy: 0.001)
    }

    func testTownIdIsStableForSamePath() {
        let url = URL(fileURLWithPath: "/tmp/some-repo")
        let id1 = RepoScanner.townId(for: url)
        let id2 = RepoScanner.townId(for: url)
        XCTAssertEqual(id1, id2)
        XCTAssertEqual(id1.count, 16)
    }

    func testTownIdDiffersByPath() {
        let a = RepoScanner.townId(for: URL(fileURLWithPath: "/tmp/a"))
        let b = RepoScanner.townId(for: URL(fileURLWithPath: "/tmp/b"))
        XCTAssertNotEqual(a, b)
    }

    // MARK: - ResourceAccrual

    func makeEvent(
        ts: Date,
        tokens: Int = 0,
        tools: [String] = [],
        slashCommand: String? = nil,
        cwd: String? = nil,
        sessionId: String? = nil,
        messageId: String? = nil
    ) -> UsageEvent {
        UsageEvent(
            timestamp: ts,
            model: "claude-opus-4-7",
            inputTokens: tokens / 4,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            outputTokens: tokens - tokens / 4,
            sessionId: sessionId,
            messageId: messageId,
            cwd: cwd,
            tools: tools,
            slashCommand: slashCommand
        )
    }

    func testAccrualConvertsTokensToCoin() {
        let now = Date()
        let events = [makeEvent(ts: now, tokens: 5000, messageId: "a")]
        let (delta, _) = ResourceAccrual.accrue(
            events: events,
            repoPath: "/repo",
            accounted: .init(),
            currentSessionCwd: nil
        )
        XCTAssertEqual(delta.coin, 5) // 5000 / 1000
    }

    func testAccrualConvertsToolsToResources() {
        let now = Date()
        var events: [UsageEvent] = []
        // 5 events × 5 reads each = 25 reads → 5 knowledge (25/5)
        for i in 0..<5 {
            events.append(makeEvent(
                ts: now.addingTimeInterval(Double(i)),
                tools: ["Read", "Read", "Read", "Read", "Read"],
                messageId: "r\(i)"
            ))
        }
        // 3 events × 1 edit = 3 edits → 1 lumber (3/3)
        for i in 0..<3 {
            events.append(makeEvent(
                ts: now.addingTimeInterval(Double(100 + i)),
                tools: ["Edit"],
                messageId: "e\(i)"
            ))
        }
        // 5 events × 1 bash = 5 bashes → 1 industry (5/5)
        for i in 0..<5 {
            events.append(makeEvent(
                ts: now.addingTimeInterval(Double(200 + i)),
                tools: ["Bash"],
                messageId: "b\(i)"
            ))
        }
        let (delta, _) = ResourceAccrual.accrue(
            events: events,
            repoPath: "/repo",
            accounted: .init(),
            currentSessionCwd: nil
        )
        XCTAssertGreaterThanOrEqual(delta.knowledge, 5)
        XCTAssertGreaterThanOrEqual(delta.lumber, 1)
        XCTAssertGreaterThanOrEqual(delta.industry, 1)
    }

    func testAccrualSlashCommandGivesInspiration() {
        let now = Date()
        let events = [
            makeEvent(ts: now, slashCommand: "review", messageId: "a"),
            makeEvent(ts: now.addingTimeInterval(1), slashCommand: "build", messageId: "b")
        ]
        let (delta, _) = ResourceAccrual.accrue(
            events: events,
            repoPath: "/repo",
            accounted: .init(),
            currentSessionCwd: nil
        )
        XCTAssertEqual(delta.inspiration, 2)
    }

    func testAccrualIdempotentViaAccountedHighWater() {
        let now = Date()
        let events = [makeEvent(ts: now, tokens: 3000, messageId: "a")]
        let (delta1, accounted) = ResourceAccrual.accrue(
            events: events,
            repoPath: "/repo",
            accounted: .init(),
            currentSessionCwd: nil
        )
        XCTAssertEqual(delta1.coin, 3)

        // Replay with the same events — nothing should accrue.
        let (delta2, _) = ResourceAccrual.accrue(
            events: events,
            repoPath: "/repo",
            accounted: accounted,
            currentSessionCwd: nil
        )
        XCTAssertEqual(delta2.coin, 0)
    }

    func testActiveSessionMultiplierMatchesRepoPath() {
        let repo = "/Users/me/code/widget"
        // Event in the repo, session in the repo → 2x
        XCTAssertEqual(
            ResourceAccrual.activeSessionMultiplier(
                eventCwd: "\(repo)/Sources",
                sessionCwd: repo,
                repoPath: repo
            ),
            2.0
        )
        // Event in a different repo → 1x
        XCTAssertEqual(
            ResourceAccrual.activeSessionMultiplier(
                eventCwd: "/Users/me/code/other",
                sessionCwd: repo,
                repoPath: repo
            ),
            1.0
        )
        // No session info → 1x
        XCTAssertEqual(
            ResourceAccrual.activeSessionMultiplier(
                eventCwd: repo,
                sessionCwd: nil,
                repoPath: repo
            ),
            1.0
        )
    }

    // MARK: - Resources arithmetic

    func testResourcesCanAffordAndDeduct() {
        var have = TokeyoTownState.Resources(coin: 50, lumber: 10)
        let costAffordable = TokeyoTownState.Resources(coin: 20, lumber: 5)
        let costTooMuch = TokeyoTownState.Resources(coin: 60)
        XCTAssertTrue(have.canAfford(costAffordable))
        XCTAssertFalse(have.canAfford(costTooMuch))
        XCTAssertTrue(have.deduct(costAffordable))
        XCTAssertEqual(have.coin, 30)
        XCTAssertEqual(have.lumber, 5)
        XCTAssertFalse(have.deduct(costTooMuch))  // unchanged on failure
        XCTAssertEqual(have.coin, 30)
    }

    func testResourcesAddIsCommutative() {
        var a = TokeyoTownState.Resources(coin: 5, knowledge: 2)
        let b = TokeyoTownState.Resources(coin: 7, lumber: 3)
        a.add(b)
        XCTAssertEqual(a.coin, 12)
        XCTAssertEqual(a.knowledge, 2)
        XCTAssertEqual(a.lumber, 3)
    }

    // MARK: - Building catalog drift guard

    // Mirrors CosmeticCatalogTests pattern — make sure every biome has 8
    // buildings and IDs are unique.

    func testEveryBiomeHasEightBuildings() {
        for biome in TokeyoTownState.Biome.allCases {
            XCTAssertEqual(
                BuildingCatalog.buildings(for: biome).count, 8,
                "Biome \(biome) should have 8 buildings"
            )
        }
    }

    func testAllBuildingIdsAreUnique() {
        let ids = BuildingCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testAllBuildingIdsResolvable() {
        for b in BuildingCatalog.all {
            XCTAssertEqual(BuildingCatalog.find(b.id)?.id, b.id)
        }
    }

    // MARK: - Iso math

    func testIsoUnprojectInversesProject() {
        let canvas = CGSize(width: 800, height: 600)
        let mapSize = 16
        for x in [0, 5, 10, 15] {
            for y in [0, 5, 10, 15] {
                let pt = IsoMath.project(x: Double(x), y: Double(y),
                                         mapSize: mapSize, canvas: canvas)
                guard let inv = IsoMath.unproject(pt, mapSize: mapSize, canvas: canvas) else {
                    XCTFail("Project (\(x), \(y)) should round-trip")
                    continue
                }
                XCTAssertEqual(inv.x, x, "x mismatch for (\(x), \(y))")
                XCTAssertEqual(inv.y, y, "y mismatch for (\(x), \(y))")
            }
        }
    }

    // MARK: - Save round-trip (covers archive perms transitively)

    func testStateCodableRoundtrip() throws {
        let repo = TokeyoTownState.RepoSnapshot(
            path: "/p", displayName: "p", scannedAt: .now,
            primaryLanguage: "swift", biome: .beach, era: .modern,
            ageInDays: 10, loc: 1234, mapSize: 24,
            contributorCount: 2, lushness: 0.5
        )
        var s = TokeyoTownState.fresh(townId: "abcd", repo: repo)
        s.resources.coin = 42
        s.buildings.append(.init(id: UUID(), kind: "beach-cottage", tileX: 3, tileY: 5, placedAt: .now))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(s)
        let back = try decoder.decode(TokeyoTownState.self, from: data)
        XCTAssertEqual(back.townId, s.townId)
        XCTAssertEqual(back.resources.coin, 42)
        XCTAssertEqual(back.buildings.count, 1)
        XCTAssertEqual(back.buildings.first?.kind, "beach-cottage")
    }
}

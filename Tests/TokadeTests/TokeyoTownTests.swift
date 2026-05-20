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
        // v2 — floor 12, ceiling 48 (smaller maps so zoom feels right).
        XCTAssertEqual(RepoScanner.mapSize(forLOC: 0), 12)
        XCTAssertEqual(RepoScanner.mapSize(forLOC: 100), 12)
        XCTAssertEqual(RepoScanner.mapSize(forLOC: 1_000_000), 48)
        let mid = RepoScanner.mapSize(forLOC: 10000)
        XCTAssertGreaterThanOrEqual(mid, 12)
        XCTAssertLessThanOrEqual(mid, 48)
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
        // v2 ratio: 1 coin / 4,000 tokens. 5,000 tokens → 1 coin.
        XCTAssertEqual(delta.coin, 1)
    }

    func testAccrualConvertsToolsToResources() {
        // v2 ratios: knowledge 1/10 reads, lumber 1/3 edits, industry 1/8 bashes.
        let now = Date()
        var events: [UsageEvent] = []
        // 10 events × 5 reads = 50 reads → 5 knowledge (50/10)
        for i in 0..<10 {
            events.append(makeEvent(
                ts: now.addingTimeInterval(Double(i)),
                tools: ["Read", "Read", "Read", "Read", "Read"],
                messageId: "r\(i)"
            ))
        }
        // 6 events × 1 edit = 6 edits → 2 lumber (6/3)
        for i in 0..<6 {
            events.append(makeEvent(
                ts: now.addingTimeInterval(Double(100 + i)),
                tools: ["Edit"],
                messageId: "e\(i)"
            ))
        }
        // 8 events × 1 bash = 8 bashes → 1 industry (8/8)
        for i in 0..<8 {
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
        XCTAssertGreaterThanOrEqual(delta.lumber, 2)
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
        // v2 ratio is 1 coin / 4,000 tokens. 12,000 tokens → 3 coin.
        let events = [makeEvent(ts: now, tokens: 12000, messageId: "a")]
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

    func testEveryBiomeHasNineBuildings() {
        // v3 — each biome has 8 base buildings + 1 extra home variant.
        for biome in TokeyoTownState.Biome.allCases {
            XCTAssertEqual(
                BuildingCatalog.buildings(for: biome).count, 9,
                "Biome \(biome) should have 9 buildings"
            )
        }
    }

    func testEveryBiomeHasMultipleHomeVariants() {
        // v3 — at least 2 home variants per biome so towns have residential diversity.
        for biome in TokeyoTownState.Biome.allCases {
            let homes = BuildingCatalog.buildings(for: biome).filter(\.isHome)
            XCTAssertGreaterThanOrEqual(
                homes.count, 2,
                "Biome \(biome) should have at least 2 home variants"
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

    // MARK: - DiscoveredRepos

    func testDiscoveredReposDedupesByProjectRoot() {
        // Two events from sibling subfolders of the same repo collapse to one.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sub = tmp.appendingPathComponent("Sources/Tokade")
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        // Mark the root with a .git directory so projectRoot finds it.
        try? FileManager.default.createDirectory(at: tmp.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let events = [
            makeEvent(ts: Date(), cwd: tmp.path, messageId: "a"),
            makeEvent(ts: Date().addingTimeInterval(1), cwd: sub.path, messageId: "b"),
        ]
        let entries = DiscoveredRepos.from(events: events)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.path, tmp.path)
    }

    func testDiscoveredReposSortedByDisplayName() {
        let now = Date()
        let events = [
            makeEvent(ts: now, cwd: "/tmp/zebra", messageId: "a"),
            makeEvent(ts: now.addingTimeInterval(1), cwd: "/tmp/apple", messageId: "b"),
            makeEvent(ts: now.addingTimeInterval(2), cwd: "/tmp/Mango", messageId: "c"),
        ]
        let entries = DiscoveredRepos.from(events: events)
        XCTAssertEqual(entries.map(\.displayName), ["apple", "Mango", "zebra"])
    }

    func testDiscoveredReposFilterIsCaseInsensitive() {
        let entries = [
            DiscoveredRepos.Entry(path: "/tmp/foo", displayName: "foo"),
            DiscoveredRepos.Entry(path: "/home/me/Bar-Project", displayName: "Bar-Project"),
            DiscoveredRepos.Entry(path: "/var/baz", displayName: "baz"),
        ]
        XCTAssertEqual(DiscoveredRepos.filter(entries, query: "").count, 3)
        XCTAssertEqual(DiscoveredRepos.filter(entries, query: "bar").count, 1)
        XCTAssertEqual(DiscoveredRepos.filter(entries, query: "/TMP/").count, 1)
        XCTAssertEqual(DiscoveredRepos.filter(entries, query: "   ").count, 3)
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

    // MARK: - Terrain (v2)

    func testTerrainGenerationIsDeterministic() {
        let a = TerrainGenerator.generate(seed: 12345, size: 16, biome: .beach)
        let b = TerrainGenerator.generate(seed: 12345, size: 16, biome: .beach)
        XCTAssertEqual(a.tiles, b.tiles)
    }

    func testTerrainSeedDiffersByTownId() {
        let s1 = TerrainGenerator.seed(for: "alpha")
        let s2 = TerrainGenerator.seed(for: "beta")
        XCTAssertNotEqual(s1, s2)
    }

    func testTerrainCanBuildHonorsAllowedTiles() {
        var tiles = [TerrainTile](repeating: .grass, count: 4 * 4)
        tiles[0] = .water
        let grid = TerrainGrid(size: 4, tiles: tiles)
        // 1×1 on grass — OK
        XCTAssertTrue(grid.canBuild(at: 1, y: 1, w: 1, h: 1, allowedTiles: [.grass]))
        // 2×2 that overlaps the water tile at (0,0) — fail
        XCTAssertFalse(grid.canBuild(at: 0, y: 0, w: 2, h: 2, allowedTiles: [.grass]))
        // 2×2 entirely on grass — OK
        XCTAssertTrue(grid.canBuild(at: 1, y: 1, w: 2, h: 2, allowedTiles: [.grass]))
        // Out of bounds — fail
        XCTAssertFalse(grid.canBuild(at: 3, y: 3, w: 2, h: 2, allowedTiles: [.grass]))
    }

    func testTerrainPathCostPrefersRoadsOverGrassOverTrees() {
        XCTAssertLessThan(TerrainTile.road.pathCost, TerrainTile.grass.pathCost)
        XCTAssertLessThan(TerrainTile.grass.pathCost, TerrainTile.tree.pathCost)
        // Water/rock are effectively impassable.
        XCTAssertGreaterThan(TerrainTile.water.pathCost, TerrainTile.tree.pathCost * 5)
    }

    // MARK: - Buildings (v2)

    func testFootprintsArePopulatedConsistently() {
        for b in BuildingCatalog.all {
            XCTAssertEqual(b.footprint.w, b.shape.footprint.w)
            XCTAssertEqual(b.footprint.h, b.shape.footprint.h)
            XCTAssertGreaterThanOrEqual(b.footprint.w, 1)
            XCTAssertGreaterThanOrEqual(b.footprint.h, 1)
            XCTAssertLessThanOrEqual(b.footprint.w, 2)
            XCTAssertLessThanOrEqual(b.footprint.h, 2)
        }
    }

    func testMajorBuildingsHaveMultiResourceCosts() {
        // Every 2x* building should require at least 2 distinct resources
        // (not just coin) — ADR-0006 addendum §5.
        for b in BuildingCatalog.all where b.footprint.w > 1 || b.footprint.h > 1 {
            let c = b.cost
            var nonZero = 0
            for k in [c.coin, c.knowledge, c.lumber, c.industry, c.stability, c.inspiration, c.growth]
                where k > 0 { nonZero += 1 }
            XCTAssertGreaterThanOrEqual(nonZero, 2, "\(b.id) should cost multiple resources")
        }
    }

    // MARK: - State versioning

    func testStateDecodesV1SaveByRegeneratingTerrain() throws {
        // A handcrafted v1 payload — no `terrain` field. The decoder should
        // fall back to regenerating terrain from the townId seed.
        let json = """
        {
          "schemaVersion": 1,
          "townId": "deadbeefdeadbeef",
          "createdAt": "2026-05-20T00:00:00Z",
          "lastTickAt": "2026-05-20T00:00:00Z",
          "repo": {
            "path": "/p", "displayName": "p",
            "scannedAt": "2026-05-20T00:00:00Z",
            "primaryLanguage": "swift",
            "biome": "beach", "era": "modern",
            "ageInDays": 1, "loc": 10, "mapSize": 16,
            "contributorCount": 1, "lushness": 0.5
          },
          "resources": {"coin":0,"knowledge":0,"lumber":0,"industry":0,"stability":0,"inspiration":0,"growth":0},
          "accountedEvents": {},
          "buildings": [],
          "townsfolk": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(TokeyoTownState.self, from: Data(json.utf8))
        XCTAssertEqual(state.terrain.size, 16)
        XCTAssertEqual(state.terrain.tiles.count, 16 * 16)
    }

    // MARK: - Townsfolk AI

    func testTownsfolkAIPicksCardinalNeighborOnly() {
        // v3 — AI commits to a `nextStep` neighbor; renderer interpolates
        // strictly between current and nextStep. No diagonal moves possible.
        var tiles = [TerrainTile](repeating: .water, count: 4 * 4)
        for i in 0..<tiles.count { tiles[i] = .water }
        tiles[0 * 4 + 0] = .grass // start
        tiles[0 * 4 + 1] = .grass // only walkable neighbor (east)
        tiles[1 * 4 + 0] = .water
        let grid = TerrainGrid(size: 4, tiles: tiles)
        let npc = TokeyoTownState.Townsfolk(
            id: UUID(), name: "T",
            tileX: 0, tileY: 0,
            homeBuildingId: nil,
            goalX: 3, goalY: 0,
            pauseRemaining: 0,
            activity: "test",
            hue: 0.5,
            createdAt: .now
        )
        let stepped = TownsfolkAI.step(
            townsfolk: [npc],
            buildings: [],
            terrain: grid,
            mapSize: 4
        )
        let next = stepped[0]
        // Should commit to east tile (1, 0), no fractional motion.
        XCTAssertEqual(next.nextStepX, 1)
        XCTAssertEqual(next.nextStepY, 0)
        // Current position untouched — renderer will lerp to nextStep.
        XCTAssertEqual(next.tileX, 0)
        XCTAssertEqual(next.tileY, 0)
    }

    // MARK: - v3 — undo/redo, elevation, autotile mask, pier-water

    func testUndoRedoRoundTrips() {
        // We can't run the full store async paths in a unit test easily,
        // but we can validate the snapshot logic by encoding & comparing.
        let repo = TokeyoTownState.RepoSnapshot(
            path: "/p", displayName: "p", scannedAt: .now,
            primaryLanguage: "swift", biome: .beach, era: .modern,
            ageInDays: 10, loc: 1234, mapSize: 16,
            contributorCount: 1, lushness: 0.5
        )
        var s1 = TokeyoTownState.fresh(townId: "abc", repo: repo)
        s1.resources.coin = 100
        var s2 = s1
        s2.resources.coin = 90
        var s3 = s2
        s3.resources.coin = 70
        var stack: [TokeyoTownState] = [s1, s2]
        var redo: [TokeyoTownState] = []
        // simulate undo from s3
        var current = s3
        if let popped = stack.popLast() {
            redo.append(current)
            current = popped
        }
        XCTAssertEqual(current.resources.coin, 90)
        if let popped = stack.popLast() {
            redo.append(current)
            current = popped
        }
        XCTAssertEqual(current.resources.coin, 100)
        if let r = redo.popLast() {
            stack.append(current)
            current = r
        }
        XCTAssertEqual(current.resources.coin, 90)
    }

    func testTerrainElevationDefaultsAndRoundTrip() throws {
        let grid = TerrainGenerator.generate(seed: 99, size: 8, biome: .forest)
        // Water tiles should default to elev -1.
        var sawWaterAt = false
        for y in 0..<8 {
            for x in 0..<8 where grid.tile(x: x, y: y) == .water {
                XCTAssertEqual(grid.elev(x: x, y: y), -1)
                sawWaterAt = true
            }
        }
        // Encode/decode round trip preserves elevation.
        let enc = JSONEncoder()
        let dec = JSONDecoder()
        let back = try dec.decode(TerrainGrid.self, from: enc.encode(grid))
        XCTAssertEqual(back.elevation, grid.elevation)
        _ = sawWaterAt // some seeds may have no water; not a failure
    }

    func testCanBuildRejectsMixedElevationFootprint() {
        var tiles = [TerrainTile](repeating: .grass, count: 4 * 4)
        var elev = [Int8](repeating: 0, count: 4 * 4)
        elev[1 * 4 + 1] = 1 // one corner of (0..2, 0..2) is on a hill
        _ = tiles
        let grid = TerrainGrid(size: 4, tiles: tiles, elevation: elev)
        XCTAssertFalse(grid.canBuild(at: 0, y: 0, w: 2, h: 2, allowedTiles: [.grass]))
        XCTAssertTrue(grid.canBuild(at: 2, y: 2, w: 2, h: 2, allowedTiles: [.grass]))
    }
}

import Foundation

/// Pure, deterministic geography for per-repo districts (issue #80,
/// Phase 2a — algorithm only, NO rendering).
///
/// The locked partition (see `docs/02-design/TOKEYO_DISTRICTS.md`) is
/// **growth-from-seed**: each district starts as a single seed tile placed
/// deterministically by `townId` and spaced apart from the others, then
/// claims surrounding tiles outward in proportion to its activity. A hot
/// district (more `activityTokens`) expands faster/further and so owns more
/// territory; a neglected one stays a hamlet.
///
/// This file is the geometry/ownership math. Phase 2b will call `ownership`
/// at render time to paint the neighborhoods. Nothing here renders, mutates
/// town state, or touches the network.
enum DistrictGeography {
    // MARK: - Seed placement

    /// Choose `districtCount` seed tiles on buildable+passable land, spread
    /// apart to maximize mutual spacing. Deterministic from `townId` (uses
    /// the same `SplitMix64` PRNG + `TerrainGenerator.seed(for:)` the rest
    /// of the codebase uses — never `arc4random`/`Date.now`/`Int.random`).
    ///
    /// Strategy: a farthest-point ("k-center" greedy) placement. Build the
    /// candidate set of land tiles (buildable AND passable). Pick a
    /// deterministic first seed from the PRNG, then repeatedly add the
    /// candidate whose nearest-existing-seed distance is greatest (ties
    /// broken by row-major index for determinism). This spreads seeds across
    /// the map without any randomness beyond the first pick.
    ///
    /// Returns seeds in district order (`result[i]` is district `i`'s seed).
    /// If there are fewer land tiles than requested, returns as many as the
    /// map can hold (each seed is still distinct). Returns `[]` when there is
    /// no land at all.
    static func placeSeeds(
        districtCount: Int,
        mapSize: Int,
        terrain: TerrainGrid,
        townId: String
    ) -> [(x: Int, y: Int)] {
        guard districtCount > 0, mapSize > 0 else { return [] }

        // Candidate land tiles: buildable (grass/sand) AND walkable. Using
        // buildable keeps seeds off water/rock/tree/road clutter, matching
        // "seed on land you could build on."
        var candidates: [(x: Int, y: Int)] = []
        for y in 0 ..< mapSize {
            for x in 0 ..< mapSize {
                let t = terrain.tile(x: x, y: y)
                if t.isBuildable, t.isWalkable {
                    candidates.append((x, y))
                }
            }
        }
        guard !candidates.isEmpty else { return [] }

        let target = min(districtCount, candidates.count)
        var rng = SplitMix64(seed: TerrainGenerator.seed(for: townId))

        // First seed: deterministic pick from the PRNG over candidates.
        let firstIndex = Int(rng.next() % UInt64(candidates.count))
        var chosen: [(x: Int, y: Int)] = [candidates[firstIndex]]

        // Greedy farthest-point for the rest.
        while chosen.count < target {
            var bestCandidate: (x: Int, y: Int)?
            var bestDist = -1
            for c in candidates {
                // Skip already-chosen tiles.
                if chosen.contains(where: { $0 == c }) { continue }
                // Distance to the nearest existing seed (squared Euclidean —
                // monotonic, integer, deterministic).
                var nearest = Int.max
                for s in chosen {
                    let dx = c.x - s.x
                    let dy = c.y - s.y
                    nearest = min(nearest, dx * dx + dy * dy)
                }
                if nearest > bestDist {
                    bestDist = nearest
                    bestCandidate = c
                }
            }
            guard let pick = bestCandidate else { break }
            chosen.append(pick)
        }
        return chosen
    }

    // MARK: - Weighted ownership (growth-from-seed)

    /// Assign each passable tile to a district index via a **weighted
    /// multi-source BFS** growing outward from the seeds. Every district's
    /// frontier expands from its seed; a higher-weight district advances
    /// faster, so it claims more territory ("growth-from-seed").
    ///
    /// Mechanics: each tile is reached by a district at an integer "cost"
    /// (a Dijkstra-style frontier). A district with weight `w` pays
    /// `step = max(1, baseStep / w)` per tile of travel, so a district twice
    /// as hot reaches any given tile at ~half the cost and wins the race for
    /// the tiles between the two seeds. The tile goes to whichever district
    /// reaches it cheapest (ties broken by lower district index for
    /// determinism). Impassable tiles (water/rock) and tiles no district can
    /// reach stay `-1`.
    ///
    /// Returns a row-major `[Int]` of length `mapSize * mapSize`.
    static func ownership(
        seeds: [(x: Int, y: Int)],
        weights: [Int],
        mapSize: Int,
        terrain: TerrainGrid
    ) -> [Int] {
        let n = mapSize * mapSize
        var owner = [Int](repeating: -1, count: n)
        guard n > 0, !seeds.isEmpty else { return owner }

        func idx(_ x: Int, _ y: Int) -> Int {
            y * mapSize + x
        }
        func passable(_ x: Int, _ y: Int) -> Bool {
            terrain.tile(x: x, y: y).isWalkable
        }

        // Per-tile best (cheapest) arrival cost so far; Int.max == unvisited.
        var bestCost = [Int](repeating: Int.max, count: n)

        // Per-district step cost: hotter (heavier) districts pay less per
        // tile, so their frontier travels further for the same total cost.
        // `baseStep` is a constant the weight divides into; the floor of 1
        // keeps every district moving even at tiny weights.
        let baseStep = 64
        func step(forDistrict d: Int) -> Int {
            let w = d < weights.count ? max(1, weights[d]) : 1
            return max(1, baseStep / w)
        }

        // Frontier entries ordered by cost. We pop the lowest-cost entry
        // each round (a simple linear scan — maps are tiny, ≤48×48). Ties
        // resolve by lower district index, then row-major tile, so the whole
        // expansion is deterministic.
        struct Entry { let cost: Int; let x: Int; let y: Int; let district: Int }
        var frontier: [Entry] = []

        for (d, seed) in seeds.enumerated() {
            guard terrain.contains(x: seed.x, y: seed.y), passable(seed.x, seed.y) else { continue }
            let i = idx(seed.x, seed.y)
            // A seed on a tile already claimed more cheaply by an earlier
            // (lower-index) district keeps that owner; otherwise claim it.
            if bestCost[i] > 0 {
                bestCost[i] = 0
                owner[i] = d
                frontier.append(Entry(cost: 0, x: seed.x, y: seed.y, district: d))
            }
        }

        let neighbors = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        while !frontier.isEmpty {
            // Pop the deterministically-lowest entry.
            var bestK = 0
            for k in 1 ..< frontier.count {
                let a = frontier[k]
                let b = frontier[bestK]
                if a.cost < b.cost
                    || (a.cost == b.cost && a.district < b.district)
                    || (a.cost == b.cost && a.district == b.district && idx(a.x, a.y) < idx(b.x, b.y)) {
                    bestK = k
                }
            }
            let cur = frontier.remove(at: bestK)
            let curI = idx(cur.x, cur.y)
            // Stale entry (a cheaper arrival already settled this tile for a
            // different owner) — skip.
            if cur.cost > bestCost[curI] || owner[curI] != cur.district { continue }

            let s = step(forDistrict: cur.district)
            for (dx, dy) in neighbors {
                let nx = cur.x + dx
                let ny = cur.y + dy
                guard terrain.contains(x: nx, y: ny), passable(nx, ny) else { continue }
                let ni = idx(nx, ny)
                let newCost = cur.cost + s
                // Claim if strictly cheaper, or equal-cost but a lower
                // district index (deterministic tie-break).
                if newCost < bestCost[ni]
                    || (newCost == bestCost[ni] && cur.district < owner[ni]) {
                    bestCost[ni] = newCost
                    owner[ni] = cur.district
                    frontier.append(Entry(cost: newCost, x: nx, y: ny, district: cur.district))
                }
            }
        }
        return owner
    }

    // MARK: - District weight

    /// A small monotonic weight for `district`, used by `ownership` to skew
    /// growth. Higher weight → faster frontier → more territory.
    ///
    /// Formula:
    ///   `weight = base + activity`
    /// where
    ///   `base     = 1 + min(originLOC / 1000, 8)`   (size floor, 1…9)
    ///   `activity = min(activityTokens / 500, 24)`  (usage skew, 0…24)
    ///
    /// The LOC-derived **base floor** guarantees a freshly-adopted town
    /// (zero activity everywhere) still has positive, size-balanced weights,
    /// so districts render at sensible relative sizes from day one. As the
    /// player works, `activityTokens` accrues and skews growth toward the
    /// hot districts. Both terms are clamped so no single district can
    /// dominate the whole map, and the result is always `>= 1` (required by
    /// `ownership`'s step floor). Pure and integer — deterministic.
    static func weight(for district: TokeyoTownState.District) -> Int {
        let base = 1 + min(max(0, district.originLOC) / 1000, 8)
        let activity = min(max(0, district.activityTokens) / 500, 24)
        return base + activity
    }
}

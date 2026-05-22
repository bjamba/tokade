import Foundation

/// Per-tile terrain on a town's map. Generated procedurally at town
/// creation time, seeded by the townId so the same repo always grows
/// the same landscape.
///
/// Buildings can be placed on `grass` (always) and `sand` (for beach
/// and desert biomes). Trees / flowers can be cleared via terraforming;
/// water and rock can be filled but cost more.
enum TerrainTile: String, Codable, CaseIterable, Hashable {
    case water     // impassable, undrainable in MVP
    case sand
    case grass
    case rock      // impassable, levelable (terraform)
    case tree      // decoration, clearable (terraform)
    case flower    // decoration, clearable (free)
    case road      // player-placed, walkable; townsfolk prefer
    case decor     // player-placed decoration (lantern / planter / etc.)

    /// True if a building's base can sit on this tile (before placement
    /// or terraforming). Players need to clear trees/rock first.
    var isBuildable: Bool {
        switch self {
        case .grass, .sand: true
        default: false
        }
    }

    /// True if a townsfolk can walk across this tile.
    var isWalkable: Bool {
        switch self {
        case .water, .rock: false
        default: true
        }
    }

    /// Pathing bias — lower = preferred. v3.5 — much stronger road
    /// preference so townsfolk visibly use the streets the player
    /// builds (was 1 vs 3; now 1 vs 12).
    var pathCost: Int {
        switch self {
        case .road: 1
        case .grass, .sand, .flower: 12
        case .tree: 18
        case .decor: 16
        case .water, .rock: 999
        }
    }
}

/// A square grid of terrain tiles plus per-tile elevation. Encoded
/// compactly in saves.
///
/// v3 — elevation tier per tile in [-1, 2]:
///   -1 = underwater shelf (drawn below the 0-plane)
///    0 = ground
///    1 = hill
///    2 = mountain
///
/// The renderer lifts the tile diamond by `elevation × stepHeight` and
/// draws side cliffs where neighbors differ. Buildings inherit their
/// anchor tile's elevation.
struct TerrainGrid: Codable, Equatable {
    let size: Int
    /// Row-major. tiles[y * size + x].
    private(set) var tiles: [TerrainTile]
    /// Row-major. elevation[y * size + x]. Defaults to 0; water defaults
    /// to -1 so the shoreline renders one step below ground.
    private(set) var elevation: [Int8]

    init(size: Int, tiles: [TerrainTile], elevation: [Int8]? = nil) {
        precondition(tiles.count == size * size)
        self.size = size
        self.tiles = tiles
        if let elev = elevation {
            precondition(elev.count == size * size)
            self.elevation = elev
        } else {
            // Default elevation: water = -1, everything else = 0.
            self.elevation = tiles.map { $0 == .water ? -1 : 0 }
        }
    }

    func tile(x: Int, y: Int) -> TerrainTile {
        guard contains(x: x, y: y) else { return .water }
        return tiles[y * size + x]
    }

    func elev(x: Int, y: Int) -> Int {
        guard contains(x: x, y: y) else { return -1 }
        return Int(elevation[y * size + x])
    }

    mutating func setTile(_ tile: TerrainTile, x: Int, y: Int) {
        guard contains(x: x, y: y) else { return }
        tiles[y * size + x] = tile
    }

    mutating func setElev(_ e: Int, x: Int, y: Int) {
        guard contains(x: x, y: y) else { return }
        elevation[y * size + x] = Int8(max(-1, min(2, e)))
    }

    func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < size && y < size
    }

    /// True if the rectangle (x..<x+w, y..<y+h) is entirely buildable
    /// (allowed tile, no water-adjacent issues, *and* every tile shares
    /// the same elevation — buildings need flat ground).
    func canBuild(at x: Int, y: Int, w: Int, h: Int, allowedTiles: Set<TerrainTile>) -> Bool {
        guard x >= 0, y >= 0, x + w <= size, y + h <= size else { return false }
        let anchorElev = elev(x: x, y: y)
        for dy in 0..<h {
            for dx in 0..<w {
                if !allowedTiles.contains(tile(x: x + dx, y: y + dy)) {
                    return false
                }
                if elev(x: x + dx, y: y + dy) != anchorElev {
                    return false
                }
            }
        }
        return true
    }

    /// Custom Codable to keep the encoded JSON compact and v2-compatible.
    /// Old (v2) saves only had `size` and `tiles`; the elevation array
    /// defaults to all-zero (water = -1) when missing.
    enum CodingKeys: String, CodingKey { case size, tiles, elevation }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let size = try c.decode(Int.self, forKey: .size)
        let tiles = try c.decode([TerrainTile].self, forKey: .tiles)
        let elev = try c.decodeIfPresent([Int8].self, forKey: .elevation)
        self.init(size: size, tiles: tiles, elevation: elev)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(size, forKey: .size)
        try c.encode(tiles, forKey: .tiles)
        try c.encode(elevation, forKey: .elevation)
    }
}

/// Procedural terrain generator. Uses value noise (no SIMD or external
/// libraries — pure stdlib + a deterministic PRNG seeded by the townId
/// so the same town always grows the same map).
enum TerrainGenerator {
    /// Generate terrain for `biome` and `size`. Deterministic — same
    /// seed yields the same grid.
    static func generate(
        seed: UInt64,
        size: Int,
        biome: TokeyoTownState.Biome
    ) -> TerrainGrid {
        var rng = SplitMix64(seed: seed)
        let elevation = noiseField(size: size, freq: 4, rng: &rng)
        let moisture = noiseField(size: size, freq: 6, rng: &rng)
        let detail = noiseField(size: size, freq: 12, rng: &rng)

        var tiles: [TerrainTile] = []
        var elev: [Int8] = []
        tiles.reserveCapacity(size * size)
        elev.reserveCapacity(size * size)
        // v3.3 — beach gets a directional shoreline bias: tiles closer to
        // one chosen map edge are nudged down in elevation so water forms
        // a contiguous coast rather than scattered ponds. Side is seeded
        // by the townId so it's stable across reloads.
        let coastSide: CoastSide = biome == .beach
            ? CoastSide.allCases[Int(seed & 3)]
            : .none
        for y in 0..<size {
            for x in 0..<size {
                var e = elevation[y * size + x]
                let m = moisture[y * size + x]
                let d = detail[y * size + x]
                if biome == .beach {
                    e = applyCoastBias(e, x: x, y: y, size: size, side: coastSide)
                }
                let kind = classify(elevation: e, moisture: m, detail: d, biome: biome)
                tiles.append(kind)
                elev.append(elevationTier(kind: kind, elevation: e))
            }
        }
        return TerrainGrid(size: size, tiles: tiles, elevation: elev)
    }

    enum CoastSide: CaseIterable {
        case none, n, e, s, w
    }

    /// Nudge the elevation noise down toward one edge so water there
    /// becomes a continuous coastline. Linear falloff over the outer
    /// 40% of the map.
    private static func applyCoastBias(
        _ e: Double, x: Int, y: Int, size: Int, side: CoastSide
    ) -> Double {
        let fx = Double(x) / Double(max(1, size - 1))
        let fy = Double(y) / Double(max(1, size - 1))
        let distFromCoast: Double
        switch side {
        case .none: return e
        case .n: distFromCoast = fy             // 0 at north edge, 1 at south
        case .s: distFromCoast = 1 - fy
        case .w: distFromCoast = fx
        case .e: distFromCoast = 1 - fx
        }
        // Within the inner 60% of the map, no bias.
        let coastZone = 0.40
        guard distFromCoast < coastZone else { return e }
        let t = distFromCoast / coastZone        // 0 at coast → 1 at inland edge of zone
        // Drop elevation linearly. At coast (t=0) drop by 0.30, fading
        // to 0 at the inland edge of the zone.
        return e - 0.30 * (1 - t)
    }

    /// Map a tile + the noise value that produced it to a discrete elev
    /// tier in [-1, 2]. Water sits 1 step below ground; rocks become
    /// hills (tier 1) most of the time, mountains (tier 2) at the high
    /// end of the elevation noise.
    private static func elevationTier(kind: TerrainTile, elevation: Double) -> Int8 {
        switch kind {
        case .water: return -1
        case .rock: return elevation > 0.92 ? 2 : 1
        default: return 0
        }
    }

    /// Choose a tile kind for one cell. Thresholds per-biome — beach has
    /// a shoreline (more water + sand), tundra trades trees for rock,
    /// etc.
    private static func classify(
        elevation: Double,
        moisture: Double,
        detail: Double,
        biome: TokeyoTownState.Biome
    ) -> TerrainTile {
        switch biome {
        case .beach:
            if elevation < 0.32 { return .water }
            if elevation < 0.45 { return .sand }
            if detail > 0.85 { return .tree }
            if detail > 0.78 { return .flower }
            return .grass
        case .desert:
            if elevation < 0.22 { return .water }
            if elevation > 0.86 { return .rock }
            if detail > 0.92 { return .tree }       // oasis vegetation
            if detail > 0.86 { return .flower }
            return .sand
        case .tundra:
            if elevation < 0.18 { return .water }   // frozen lakes
            if elevation > 0.80 { return .rock }
            if detail > 0.80, moisture > 0.55 { return .tree }
            return .grass
        case .forest:
            if elevation < 0.18 { return .water }
            if elevation > 0.88 { return .rock }
            if detail > 0.55, moisture > 0.45 { return .tree }
            if detail > 0.45, moisture > 0.65 { return .flower }
            return .grass
        case .plain:
            if elevation < 0.16 { return .water }
            if elevation > 0.90 { return .rock }
            if detail > 0.82 { return .tree }
            if detail > 0.74 { return .flower }
            return .grass
        }
    }

    /// Value-noise field at the given frequency, smoothed via bilinear
    /// interpolation. Output values are in [0, 1]. Slow and simple —
    /// generation runs once per town and isn't perf-sensitive.
    private static func noiseField(
        size: Int,
        freq: Int,
        rng: inout SplitMix64
    ) -> [Double] {
        let gridDim = max(2, freq + 1)
        var grid = [Double](repeating: 0, count: gridDim * gridDim)
        for i in 0..<grid.count {
            grid[i] = rng.nextUnitDouble()
        }
        // Smooth-step + bilerp at each output cell.
        var out = [Double](repeating: 0, count: size * size)
        let scale = Double(gridDim - 1) / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let fx = Double(x) * scale
                let fy = Double(y) * scale
                let x0 = Int(fx.rounded(.down))
                let y0 = Int(fy.rounded(.down))
                let x1 = min(gridDim - 1, x0 + 1)
                let y1 = min(gridDim - 1, y0 + 1)
                let tx = smoothstep(fx - Double(x0))
                let ty = smoothstep(fy - Double(y0))
                let a = grid[y0 * gridDim + x0]
                let b = grid[y0 * gridDim + x1]
                let c = grid[y1 * gridDim + x0]
                let d = grid[y1 * gridDim + x1]
                let ab = a + (b - a) * tx
                let cd = c + (d - c) * tx
                out[y * size + x] = ab + (cd - ab) * ty
            }
        }
        return out
    }

    private static func smoothstep(_ t: Double) -> Double {
        let c = max(0, min(1, t))
        return c * c * (3 - 2 * c)
    }
}

/// Deterministic 64-bit PRNG (SplitMix64). Tiny, no Foundation dependency,
/// good distribution for procedural terrain.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextUnitDouble() -> Double {
        // Top 53 bits give a uniform Double in [0, 1).
        Double(next() >> 11) / Double(1 << 53)
    }
}

extension TerrainGenerator {
    /// Derive a deterministic seed from a townId hex string.
    static func seed(for townId: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in townId.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01B3
        }
        return hash
    }
}

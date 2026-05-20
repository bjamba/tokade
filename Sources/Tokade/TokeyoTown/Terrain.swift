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

    /// Pathing bias — lower = preferred. Roads are cheapest, decor / trees
    /// add a small cost so townsfolk go around when possible.
    var pathCost: Int {
        switch self {
        case .road: 1
        case .grass, .sand, .flower: 3
        case .tree: 6
        case .decor: 5
        case .water, .rock: 99
        }
    }
}

/// A square grid of terrain tiles. Encoded compactly (one row string per
/// row, single character per tile) so saves stay readable.
struct TerrainGrid: Codable, Equatable {
    let size: Int
    /// Row-major. tiles[y * size + x].
    private(set) var tiles: [TerrainTile]

    init(size: Int, tiles: [TerrainTile]) {
        precondition(tiles.count == size * size)
        self.size = size
        self.tiles = tiles
    }

    func tile(x: Int, y: Int) -> TerrainTile {
        guard contains(x: x, y: y) else { return .water }
        return tiles[y * size + x]
    }

    mutating func setTile(_ tile: TerrainTile, x: Int, y: Int) {
        guard contains(x: x, y: y) else { return }
        tiles[y * size + x] = tile
    }

    func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < size && y < size
    }

    /// True if the rectangle (x..<x+w, y..<y+h) is entirely buildable
    /// (grass/sand for the building's allowed terrain set, no occupants).
    func canBuild(at x: Int, y: Int, w: Int, h: Int, allowedTiles: Set<TerrainTile>) -> Bool {
        guard x >= 0, y >= 0, x + w <= size, y + h <= size else { return false }
        for dy in 0..<h {
            for dx in 0..<w {
                if !allowedTiles.contains(tile(x: x + dx, y: y + dy)) {
                    return false
                }
            }
        }
        return true
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
        tiles.reserveCapacity(size * size)
        for y in 0..<size {
            for x in 0..<size {
                let e = elevation[y * size + x]
                let m = moisture[y * size + x]
                let d = detail[y * size + x]
                tiles.append(classify(elevation: e, moisture: m, detail: d, biome: biome))
            }
        }
        return TerrainGrid(size: size, tiles: tiles)
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

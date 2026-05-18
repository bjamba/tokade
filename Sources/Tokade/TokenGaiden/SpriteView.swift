import SwiftUI

/// Animates a Tokegotchi sprite through a sequence of matrix frames using a
/// chosen palette. Renders at integer pixel scale via `SpriteRenderer`.
@MainActor
struct SpriteView: View {
    let frames: [SpriteMatrix]
    let palette: Palette
    var scale: Int = 6
    var fps: Double = 4
    var crt: CRTMode = .off
    /// Manual frame override (testing / preview); when nil the view animates.
    var pinnedFrame: Int?

    var body: some View {
        // TimelineView drives the redraw schedule from a system clock, which
        // means parent re-renders (e.g. user toggles CRT setting) don't strand
        // an animation loop. Frame index is purely a function of time.
        TimelineView(.periodic(from: .now, by: max(0.01, 1.0 / fps))) { context in
            let idx = pinnedFrame ?? frameIndex(at: context.date)
            let current = frames.isEmpty ? blankMatrix : frames[idx % max(frames.count, 1)]
            let image = SpriteRenderer.render(current, palette: palette, scale: scale, crt: crt)
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(
                    width: CGFloat(current.width * scale),
                    height: CGFloat(current.height * scale)
                )
                .accessibilityLabel("Tokegotchi sprite")
        }
    }

    private func frameIndex(at date: Date) -> Int {
        guard !frames.isEmpty else { return 0 }
        let seconds = date.timeIntervalSince1970
        let i = Int(seconds * fps)
        return ((i % frames.count) + frames.count) % frames.count
    }

    private var blankMatrix: SpriteMatrix {
        SpriteMatrix(width: 1, height: 1, rows: [["."]])
    }
}

/// Loads bundled matrices on demand. Caches once per app launch.
///
/// The "naked" base frames are three matrices: idle, walk-a, walk-b. Each
/// cosmetic is baked three times (one per frame) so cosmetics animate
/// together with their underlying body parts — see
/// `design/tokegotchi/bake-cosmetics-animated.sh`.
enum BundledSprites {
    // MARK: - Frame index

    /// Frame names in walk-cycle order. The breathing/animation cycle goes
    /// idle → walk-a → idle → walk-b → idle → ... so the head dips with each
    /// step and the arms counter-swing.
    static let breathingCycle: [String] = ["idle", "walk-a", "idle", "walk-b"]

    /// Single resting-pose frame.
    static let idleCycle: [String] = ["idle"]

    // MARK: - Base frames

    private static var baseCache: [String: SpriteMatrix] = [:]

    /// Load the bundled base (naked-body) matrix for a frame name.
    static func base(frame: String) -> SpriteMatrix? {
        if let cached = baseCache[frame] { return cached }
        guard let url = appBundledResource(named: frame, ext: "matrix"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let parsed = try? SpriteMatrix.parse(text) else {
            return nil
        }
        baseCache[frame] = parsed
        return parsed
    }

    // MARK: - Cosmetics

    private static var cosmeticCache: [String: SpriteMatrix?] = [:]

    /// Per-frame cosmetic overlay. Falls back to the idle variant if a
    /// per-frame matrix wasn't baked. Returns nil for cosmetics the app
    /// doesn't have bundled.
    static func cosmetic(slot: String, name: String, frame: String) -> SpriteMatrix? {
        let primaryKey = "tg-\(slot)-\(name)-\(frame)"
        if let cached = cosmeticCache[primaryKey] { return cached }
        if let m = loadMatrix(name: primaryKey) {
            cosmeticCache[primaryKey] = m
            return m
        }
        // Fall back to the frame-less (idle) variant.
        let fallbackKey = "tg-\(slot)-\(name)"
        if let cached = cosmeticCache[fallbackKey] { return cached }
        if let m = loadMatrix(name: fallbackKey) {
            cosmeticCache[fallbackKey] = m
            cosmeticCache[primaryKey] = m   // memoize the fallback too
            return m
        }
        cosmeticCache[primaryKey] = nil
        return nil
    }

    /// Compose a fully-equipped sequence of animation frames given an
    /// equipped-cosmetic map. For each frame name in `frames`, layers the
    /// per-frame cosmetic variants over the matching base frame.
    static func compose(frames: [String], equipped: [String: String?]) -> [SpriteMatrix] {
        let order: [String] = ["cape", "pants", "belt", "shirt", "hair", "eyewear", "hat", "held"]
        return frames.compactMap { frame in
            guard let baseFrame = base(frame: frame) else { return nil }
            let layers: [SpriteMatrix?] = order.map { slot in
                guard let name = equipped[slot] ?? nil else { return nil }
                return cosmetic(slot: slot, name: name, frame: frame)
            }
            return SpriteComposer.compose(base: baseFrame, orderedLayers: layers)
        }
    }

    /// Compose ONLY the listed slots over a fully-transparent base, for use
    /// as a silhouette overlay in the wardrobe preview. Returns one matrix
    /// per requested frame, each containing just the requested cosmetic
    /// layers (everything else is transparent).
    ///
    /// The caller renders the resulting matrices with `Palette.silhouette`
    /// and overlays them on the normal-rendered sprite to show locked items
    /// as shadow shapes without spoiling their actual colors.
    static func composeLayersOnly(frames: [String], equipped: [String: String?]) -> [SpriteMatrix] {
        let order: [String] = ["cape", "pants", "belt", "shirt", "hair", "eyewear", "hat", "held"]
        return frames.compactMap { frame in
            // Use the base only to learn the right dimensions; then build a
            // blank transparent matrix of the same size.
            guard let baseFrame = base(frame: frame) else { return nil }
            let w = baseFrame.width
            let h = baseFrame.height
            let blankRow = Array(repeating: Character("."), count: w)
            var rows: [[Character]] = Array(repeating: blankRow, count: h)
            for slot in order {
                guard let name = equipped[slot] ?? nil else { continue }
                guard let layer = cosmetic(slot: slot, name: name, frame: frame),
                      layer.width == w, layer.height == h
                else { continue }
                for y in 0..<h {
                    for x in 0..<w {
                        let g = layer.rows[y][x]
                        if g != "." { rows[y][x] = g }
                    }
                }
            }
            return SpriteMatrix(width: w, height: h, rows: rows)
        }
    }

    // MARK: - Internals

    private static func loadMatrix(name: String) -> SpriteMatrix? {
        guard let url = appBundledResource(named: name, ext: "matrix"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return try? SpriteMatrix.parse(text)
    }
}

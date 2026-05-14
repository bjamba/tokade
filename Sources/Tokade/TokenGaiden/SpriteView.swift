import SwiftUI

/// Animates a Tokegotchi sprite through a sequence of matrix frames using a
/// chosen palette. Renders at integer pixel scale via `SpriteRenderer`.
@MainActor
struct SpriteView: View {
    let frames: [SpriteMatrix]
    let palette: Palette
    var scale: Int = 6
    var fps: Double = 4

    @State private var frameIdx: Int = 0

    var body: some View {
        let current = frames.isEmpty ? blankMatrix : frames[frameIdx % max(frames.count, 1)]
        let image = SpriteRenderer.render(current, palette: palette, scale: scale)
        return Image(nsImage: image)
            .interpolation(.none)
            .resizable()
            .frame(
                width: CGFloat(current.width * scale),
                height: CGFloat(current.height * scale)
            )
            .accessibilityLabel("Tokegotchi sprite")
            .onAppear { startAnimating() }
    }

    private func startAnimating() {
        guard frames.count > 1, fps > 0 else { return }
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000.0 / fps))
                frameIdx = (frameIdx + 1) % frames.count
            }
        }
    }

    private var blankMatrix: SpriteMatrix {
        SpriteMatrix(width: 1, height: 1, rows: [["."]])
    }
}

/// Loads bundled matrices on demand. Caches once per app launch.
///
/// The "naked" base frames are the three idle/walk-A/walk-B frames with no
/// hair, shirt, pants, or belt. Cosmetic matrices are layered on top per
/// equipped slot.
enum BundledSprites {
    // MARK: - Base frames

    static let idle: [SpriteMatrix] = loadFrames(["idle"])
    static let walk: [SpriteMatrix] = loadFrames(["walk-a", "walk-b"])
    /// Idle + slight alternation that reads as a breathing pet.
    static let breathing: [SpriteMatrix] = loadFrames(["idle", "walk-a", "idle", "walk-b"])

    // MARK: - Cosmetics

    private static var cosmeticCache: [String: SpriteMatrix] = [:]

    /// Look up a single cosmetic matrix by slot + name. Caches on first hit.
    /// Returns nil if the matrix isn't bundled with the app (e.g. a cosmetic
    /// authored but not yet baked). The bundle stores them flat with a
    /// `tg-<slot>-<name>.matrix` convention because SwiftPM `.process`
    /// resources don't preserve subdirectories.
    static func cosmetic(slot: String, name: String) -> SpriteMatrix? {
        let key = "tg-\(slot)-\(name)"
        if let cached = cosmeticCache[key] { return cached }
        guard let url = appBundledResource(named: key, ext: "matrix"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let parsed = try? SpriteMatrix.parse(text) else {
            return nil
        }
        cosmeticCache[key] = parsed
        return parsed
    }

    /// Compose a fully-equipped Tokegotchi from base frames + an equipment
    /// map. Z-order matches ADR-0005:
    /// cape → pants → belt → shirt → hair → eyewear → hat
    static func compose(base: [SpriteMatrix], equipped: [String: String?]) -> [SpriteMatrix] {
        let order: [String] = ["cape", "pants", "belt", "shirt", "hair", "eyewear", "hat"]
        let layers: [SpriteMatrix?] = order.map { slot in
            guard let name = equipped[slot] ?? nil else { return nil }
            return cosmetic(slot: slot, name: name)
        }
        return base.map { frame in
            SpriteComposer.compose(base: frame, orderedLayers: layers)
        }
    }

    // MARK: - Internals

    private static func loadFrames(_ names: [String]) -> [SpriteMatrix] {
        names.compactMap { name in
            guard let url = appBundledResource(named: name, ext: "matrix"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                return nil
            }
            return try? SpriteMatrix.parse(text)
        }
    }
}

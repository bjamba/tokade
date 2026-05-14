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

/// Loads the bundled animation matrices once and exposes them via a typed enum.
enum BundledSprites {
    static let idle = loadFrames(["idle"])
    static let walk = loadFrames(["walk-a", "walk-b"])
    static let breathing = loadFrames(["idle", "walk-a", "idle", "walk-b"])

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

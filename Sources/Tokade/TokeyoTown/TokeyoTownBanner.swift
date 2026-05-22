import SwiftUI

/// Arcade-launcher banner for Tokeyo Town. v3.14 — redesigned as a
/// modern cityscape silhouette: gradient night-sunset sky over a row
/// of flat-roofed skyscrapers with lit windows. Clean sans-serif title
/// stamped along the lower band. A thin CRT scanline overlay sits on
/// top so the banner reads as part of the Arcade's retro frame.
struct TokeyoTownBanner: View {
    var body: some View {
        Canvas { context, size in
            drawSky(context: context, size: size)
            drawMoon(context: context, size: size)
            drawSkyline(context: context, size: size)
            drawGroundBand(context: context, size: size)
            drawTitle(context: context, size: size)
            drawCRTOverlay(context: context, size: size)
        }
        .aspectRatio(128.0 / 48.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sky + moon

    private func drawSky(context: GraphicsContext, size: CGSize) {
        // Vertical gradient from deep indigo (top) to magenta to coral.
        let stops = [
            (CGFloat(0.0), Color(red: 0.08, green: 0.05, blue: 0.22)),
            (CGFloat(0.45), Color(red: 0.32, green: 0.12, blue: 0.42)),
            (CGFloat(0.75), Color(red: 0.85, green: 0.35, blue: 0.45)),
            (CGFloat(1.0), Color(red: 0.98, green: 0.65, blue: 0.48)),
        ]
        let bandH = size.height
        let steps = 24
        for i in 0 ..< steps {
            let t0 = CGFloat(i) / CGFloat(steps)
            let t1 = CGFloat(i + 1) / CGFloat(steps)
            let color = interp(stops: stops, t: t0)
            let rect = CGRect(x: 0, y: t0 * bandH, width: size.width,
                              height: (t1 - t0) * bandH)
            context.fill(Path(rect), with: .color(color))
        }
    }

    private func drawMoon(context: GraphicsContext, size: CGSize) {
        let r = size.height * 0.16
        let center = CGPoint(x: size.width * 0.78, y: size.height * 0.32)
        // Soft halo
        let haloRect = CGRect(x: center.x - r * 2, y: center.y - r * 2,
                              width: r * 4, height: r * 4)
        context.fill(Path(ellipseIn: haloRect),
                     with: .color(Color(red: 1, green: 0.92, blue: 0.78).opacity(0.18)))
        // Moon body
        let body = CGRect(x: center.x - r, y: center.y - r,
                          width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: body),
                     with: .color(Color(red: 0.99, green: 0.95, blue: 0.85)))
    }

    private func drawSkyline(context: GraphicsContext, size: CGSize) {
        // A row of varied-height rectangles forming a city silhouette.
        // Heights + spacing fixed so the look is deterministic.
        struct Tower {
            let leftFrac: CGFloat
            let widthFrac: CGFloat
            let heightFrac: CGFloat
        }
        let towers: [Tower] = [
            Tower(leftFrac: 0.04, widthFrac: 0.06, heightFrac: 0.42),
            Tower(leftFrac: 0.11, widthFrac: 0.08, heightFrac: 0.58),
            Tower(leftFrac: 0.20, widthFrac: 0.05, heightFrac: 0.34),
            Tower(leftFrac: 0.26, widthFrac: 0.10, heightFrac: 0.66),
            Tower(leftFrac: 0.37, widthFrac: 0.07, heightFrac: 0.48),
            Tower(leftFrac: 0.45, widthFrac: 0.12, heightFrac: 0.76),
            Tower(leftFrac: 0.58, widthFrac: 0.05, heightFrac: 0.36),
            Tower(leftFrac: 0.64, widthFrac: 0.08, heightFrac: 0.54),
            Tower(leftFrac: 0.73, widthFrac: 0.06, heightFrac: 0.40),
            Tower(leftFrac: 0.80, widthFrac: 0.09, heightFrac: 0.62),
            Tower(leftFrac: 0.90, widthFrac: 0.07, heightFrac: 0.46),
        ]
        let baseY = size.height * 0.86
        let bodyColor = Color(red: 0.08, green: 0.10, blue: 0.18)
        let bodyEdge = Color(red: 0.16, green: 0.18, blue: 0.28)
        for t in towers {
            let x = t.leftFrac * size.width
            let w = t.widthFrac * size.width
            let h = t.heightFrac * size.height
            let rect = CGRect(x: x, y: baseY - h, width: w, height: h)
            context.fill(Path(rect), with: .color(bodyColor))
            // 1px right + top highlight for a touch of depth
            var topEdge = Path()
            topEdge.move(to: CGPoint(x: rect.minX, y: rect.minY))
            topEdge.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            context.stroke(topEdge, with: .color(bodyEdge), lineWidth: 0.6)
            // Lit windows — a small grid in two warm yellows
            drawWindows(context: context, rect: rect, biasSeed: Int(t.leftFrac * 1000))
        }
    }

    private func drawWindows(context: GraphicsContext, rect: CGRect, biasSeed: Int) {
        let cellW: CGFloat = 2
        let cellH: CGFloat = 2
        let gapX: CGFloat = 2
        let gapY: CGFloat = 2
        let stride = cellH + gapY
        let columns = Int(rect.width / (cellW + gapX))
        let rows = Int((rect.height - 4) / stride)
        // Deterministic pseudo-random "lit" mask seeded by tower index.
        var seed = UInt64(biasSeed &+ 1)
        func next() -> Double {
            seed &+= 0x9E37_79B9_7F4A_7C15
            var z = seed
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            return Double(z >> 11) / Double(1 << 53)
        }
        for row in 0 ..< rows {
            for col in 0 ..< columns {
                let lit = next() < 0.55
                guard lit else { continue }
                let color = next() < 0.7
                    ? Color(red: 0.98, green: 0.88, blue: 0.42)
                    : Color(red: 0.95, green: 0.55, blue: 0.32)
                let x = rect.minX + 1 + CGFloat(col) * (cellW + gapX)
                let y = rect.maxY - 3 - CGFloat(row + 1) * stride
                let r = CGRect(x: x, y: y, width: cellW, height: cellH)
                context.fill(Path(r), with: .color(color))
            }
        }
    }

    private func drawGroundBand(context: GraphicsContext, size: CGSize) {
        let baseY = size.height * 0.86
        let band = CGRect(x: 0, y: baseY, width: size.width,
                          height: size.height - baseY)
        context.fill(Path(band), with: .color(Color(red: 0.04, green: 0.05, blue: 0.10)))
    }

    // MARK: - Title

    private func drawTitle(context: GraphicsContext, size: CGSize) {
        let title = "TOKEYO TOWN"
        // Slightly wider letterspacing achieved by drawing a single
        // string with kern attribute via AttributedString.
        var attr = AttributedString(title)
        attr.font = .system(size: size.height * 0.32,
                            weight: .heavy,
                            design: .default)
        attr.kern = size.height * 0.04
        attr.foregroundColor = .white
        let text = Text(attr)
        let resolved = context.resolve(text)
        let measured = resolved.measure(in: CGSize(width: size.width * 0.9,
                                                   height: size.height))
        let position = CGPoint(x: size.width / 2, y: size.height * 0.45)
        // Subtle drop shadow
        let shadow = context.resolve(Text(attr).foregroundColor(.black.opacity(0.6)))
        context.draw(shadow, at: CGPoint(x: position.x + 1, y: position.y + 1.5),
                     anchor: .center)
        context.draw(resolved, at: position, anchor: .center)
        _ = measured
    }

    // MARK: - CRT overlay

    private func drawCRTOverlay(context: GraphicsContext, size: CGSize) {
        // Thin horizontal scanlines + soft vignette.
        var y: CGFloat = 0
        while y < size.height {
            let line = CGRect(x: 0, y: y, width: size.width, height: 1)
            context.fill(Path(line), with: .color(Color.black.opacity(0.20)))
            y += 2
        }
        // Vignette via concentric darker rings at the edges.
        for inset in stride(from: CGFloat(0), through: CGFloat(8), by: CGFloat(2)) {
            let rect = CGRect(x: -inset, y: -inset,
                              width: size.width + inset * 2,
                              height: size.height + inset * 2)
            context.stroke(Path(rect),
                           with: .color(Color.black.opacity(0.10)),
                           lineWidth: 1)
        }
    }

    // MARK: - Gradient interp

    private func interp(stops: [(CGFloat, Color)], t: CGFloat) -> Color {
        let clamped = max(0, min(1, t))
        for i in 0 ..< stops.count - 1 {
            let (a, ca) = stops[i]
            let (b, cb) = stops[i + 1]
            if clamped >= a, clamped <= b {
                let local = (clamped - a) / max(0.0001, b - a)
                return ca.mix(with: cb, by: Double(local))
            }
        }
        return stops.last?.1 ?? .black
    }
}

extension Color {
    /// Linearly mix this color with `other` by `amount ∈ [0, 1]`.
    /// Goes through device RGB so the math is straightforward.
    func mix(with other: Color, by amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.deviceRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.deviceRGB) ?? .black
        let t = CGFloat(max(0, min(1, amount)))
        return Color(
            red: Double(a.redComponent * (1 - t) + b.redComponent * t),
            green: Double(a.greenComponent * (1 - t) + b.greenComponent * t),
            blue: Double(a.blueComponent * (1 - t) + b.blueComponent * t)
        )
    }
}

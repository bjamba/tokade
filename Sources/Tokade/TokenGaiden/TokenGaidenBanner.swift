import SwiftUI

/// Arcade-launcher banner for Token Gaiden RPG. v3.14 — Conan-the-
/// Barbarian–style high-fantasy logo: jagged mountain silhouette,
/// blood-red gradient sky, crossed swords behind the title, heavy
/// wedge-serif type carved out of stone. Topped with a thin CRT
/// scanline overlay so it sits in the same retro frame as the
/// other Arcade banner.
struct TokenGaidenBanner: View {
    var body: some View {
        Canvas { context, size in
            drawSky(context: context, size: size)
            drawMountains(context: context, size: size)
            drawCrossedSwords(context: context, size: size)
            drawTitle(context: context, size: size)
            drawCRTOverlay(context: context, size: size)
        }
        .aspectRatio(128.0 / 48.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func drawSky(context: GraphicsContext, size: CGSize) {
        // Dark crimson at the top through to fire orange at the horizon.
        let stops = [
            (CGFloat(0.0), Color(red: 0.18, green: 0.02, blue: 0.04)),
            (CGFloat(0.55), Color(red: 0.55, green: 0.10, blue: 0.10)),
            (CGFloat(0.85), Color(red: 0.92, green: 0.45, blue: 0.14)),
            (CGFloat(1.0), Color(red: 0.99, green: 0.78, blue: 0.30)),
        ]
        let steps = 28
        for i in 0 ..< steps {
            let t0 = CGFloat(i) / CGFloat(steps)
            let t1 = CGFloat(i + 1) / CGFloat(steps)
            let color = interp(stops: stops, t: t0)
            let rect = CGRect(x: 0, y: t0 * size.height, width: size.width,
                              height: (t1 - t0) * size.height)
            context.fill(Path(rect), with: .color(color))
        }
    }

    private func drawMountains(context: GraphicsContext, size: CGSize) {
        let baseY = size.height * 0.84
        // Far range — taller, lighter (looks atmospheric)
        for (cx, height, shade) in [
            (size.width * 0.18, size.height * 0.50, 0.40),
            (size.width * 0.42, size.height * 0.62, 0.30),
            (size.width * 0.66, size.height * 0.52, 0.36),
            (size.width * 0.88, size.height * 0.46, 0.42),
        ] {
            var p = Path()
            let halfW = height * 0.85
            p.move(to: CGPoint(x: cx - halfW, y: baseY))
            // Jagged peak
            p.addLine(to: CGPoint(x: cx - halfW * 0.4, y: baseY - height * 0.7))
            p.addLine(to: CGPoint(x: cx, y: baseY - height))
            p.addLine(to: CGPoint(x: cx + halfW * 0.5, y: baseY - height * 0.75))
            p.addLine(to: CGPoint(x: cx + halfW, y: baseY))
            p.closeSubpath()
            context.fill(p, with: .color(Color(red: 0.20 * shade,
                                               green: 0.06 * shade,
                                               blue: 0.08 * shade)))
        }
        // Foreground silhouette band — solid black ridge along the bottom.
        var foreground = Path()
        foreground.move(to: CGPoint(x: 0, y: baseY + size.height * 0.05))
        for x in stride(from: 0, through: size.width, by: size.width * 0.08) {
            let bump = sin(Double(x) * 0.35) * Double(size.height) * 0.02
            foreground.addLine(to: CGPoint(x: x, y: baseY + 2 + CGFloat(bump)))
        }
        foreground.addLine(to: CGPoint(x: size.width, y: size.height))
        foreground.addLine(to: CGPoint(x: 0, y: size.height))
        foreground.closeSubpath()
        context.fill(foreground, with: .color(Color(red: 0.04, green: 0.02, blue: 0.03)))
    }

    private func drawCrossedSwords(context: GraphicsContext, size: CGSize) {
        let cx = size.width / 2
        let cy = size.height * 0.50
        // Two swords crossed at 30° / -30° from vertical, behind the title.
        // Drawn dark with a thin steel highlight so they read as silhouette.
        drawSword(context: context, center: CGPoint(x: cx, y: cy),
                  length: size.height * 1.05,
                  angle: .pi / 5,
                  color: Color(red: 0.30, green: 0.30, blue: 0.34),
                  highlight: Color(red: 0.78, green: 0.78, blue: 0.84),
                  hiltColor: Color(red: 0.55, green: 0.30, blue: 0.12))
        drawSword(context: context, center: CGPoint(x: cx, y: cy),
                  length: size.height * 1.05,
                  angle: -.pi / 5,
                  color: Color(red: 0.30, green: 0.30, blue: 0.34),
                  highlight: Color(red: 0.78, green: 0.78, blue: 0.84),
                  hiltColor: Color(red: 0.55, green: 0.30, blue: 0.12))
    }

    private func drawSword(
        context: GraphicsContext,
        center: CGPoint,
        length: CGFloat,
        angle: CGFloat,
        color: Color,
        highlight: Color,
        hiltColor: Color
    ) {
        let halfL = length / 2
        let bladeW: CGFloat = 3
        let hiltW: CGFloat = 8
        let hiltH: CGFloat = 5
        let pommelR: CGFloat = 2.5
        let dir = CGVector(dx: sin(angle), dy: -cos(angle))
        let perp = CGVector(dx: -dir.dy, dy: dir.dx)
        // Tip of the blade
        let tip = CGPoint(x: center.x + dir.dx * halfL,
                          y: center.y + dir.dy * halfL)
        // Where the blade meets the cross-guard
        let guardCenter = CGPoint(x: center.x - dir.dx * halfL * 0.35,
                                  y: center.y - dir.dy * halfL * 0.35)
        // Pommel end
        let pommel = CGPoint(x: center.x - dir.dx * halfL * 0.55,
                             y: center.y - dir.dy * halfL * 0.55)
        // Blade — long diamond
        var blade = Path()
        blade.move(to: tip)
        blade.addLine(to: CGPoint(x: guardCenter.x + perp.dx * bladeW,
                                  y: guardCenter.y + perp.dy * bladeW))
        blade.addLine(to: CGPoint(x: guardCenter.x - perp.dx * bladeW,
                                  y: guardCenter.y - perp.dy * bladeW))
        blade.closeSubpath()
        context.fill(blade, with: .color(color))
        // Center highlight along the blade
        var glint = Path()
        glint.move(to: tip)
        glint.addLine(to: CGPoint(x: guardCenter.x + dir.dx * 0,
                                  y: guardCenter.y + dir.dy * 0))
        context.stroke(glint, with: .color(highlight), lineWidth: 0.6)
        // Cross-guard — perpendicular bar
        var guard_ = Path()
        guard_.move(to: CGPoint(x: guardCenter.x + perp.dx * hiltW,
                                y: guardCenter.y + perp.dy * hiltW))
        guard_.addLine(to: CGPoint(x: guardCenter.x - perp.dx * hiltW,
                                   y: guardCenter.y - perp.dy * hiltW))
        context.stroke(guard_, with: .color(hiltColor),
                       style: StrokeStyle(lineWidth: hiltH, lineCap: .round))
        // Hilt — short stick from cross-guard to pommel
        var hilt = Path()
        hilt.move(to: guardCenter)
        hilt.addLine(to: pommel)
        context.stroke(hilt, with: .color(hiltColor),
                       style: StrokeStyle(lineWidth: 3.4, lineCap: .square))
        // Pommel knob
        let pommelRect = CGRect(x: pommel.x - pommelR, y: pommel.y - pommelR,
                                width: pommelR * 2, height: pommelR * 2)
        context.fill(Path(ellipseIn: pommelRect),
                     with: .color(Color(red: 0.85, green: 0.75, blue: 0.32)))
    }

    private func drawTitle(context: GraphicsContext, size: CGSize) {
        let title = "TOKEN GAIDEN"
        let maxWidth = size.width * 0.78 // narrower than Tokeyo Town — leave room for sword tips
        let (pt, kern) = fittedFontSize(
            text: title,
            weight: .black,
            design: .serif,
            startingPt: size.height * 0.30,
            startingKern: size.height * 0.015,
            maxWidth: maxWidth,
            availableHeight: size.height,
            context: context
        )
        var attr = AttributedString(title)
        attr.font = .system(size: pt, weight: .black, design: .serif)
        attr.kern = kern
        attr.foregroundColor = Color(red: 0.96, green: 0.86, blue: 0.42)
        let resolved = context.resolve(Text(attr))

        let titleY = size.height * 0.46
        for offset in [
            (CGSize(width: 2, height: 2), 0.7),
            (CGSize(width: 1, height: 1), 0.4),
        ] {
            let shadowAttr = attr.transformedShadow(opacity: offset.1)
            let shadow = context.resolve(Text(shadowAttr))
            context.draw(shadow,
                         at: CGPoint(x: size.width / 2 + offset.0.width,
                                     y: titleY + offset.0.height),
                         anchor: .center)
        }
        context.draw(resolved, at: CGPoint(x: size.width / 2, y: titleY),
                     anchor: .center)

        var sub = AttributedString("R P G")
        sub.font = .system(size: size.height * 0.16, weight: .bold, design: .serif)
        sub.kern = size.height * 0.10
        sub.foregroundColor = Color(red: 0.78, green: 0.16, blue: 0.10)
        context.draw(context.resolve(Text(sub)),
                     at: CGPoint(x: size.width / 2, y: size.height * 0.78),
                     anchor: .center)
    }

    private func fittedFontSize(
        text: String,
        weight: Font.Weight,
        design: Font.Design,
        startingPt: CGFloat,
        startingKern: CGFloat,
        maxWidth: CGFloat,
        availableHeight: CGFloat,
        context: GraphicsContext
    ) -> (CGFloat, CGFloat) {
        var pt = startingPt
        var kern = startingKern
        for _ in 0 ..< 12 {
            var attr = AttributedString(text)
            attr.font = .system(size: pt, weight: weight, design: design)
            attr.kern = kern
            let m = context.resolve(Text(attr)).measure(
                in: CGSize(width: 10000, height: availableHeight)
            )
            if m.width <= maxWidth { return (pt, kern) }
            pt *= 0.88
            kern *= 0.88
        }
        return (pt, kern)
    }

    private func drawCRTOverlay(context: GraphicsContext, size: CGSize) {
        var y: CGFloat = 0
        while y < size.height {
            let line = CGRect(x: 0, y: y, width: size.width, height: 1)
            context.fill(Path(line), with: .color(Color.black.opacity(0.22)))
            y += 2
        }
        for inset in stride(from: CGFloat(0), through: CGFloat(8), by: CGFloat(2)) {
            let rect = CGRect(x: -inset, y: -inset,
                              width: size.width + inset * 2,
                              height: size.height + inset * 2)
            context.stroke(Path(rect),
                           with: .color(Color.black.opacity(0.10)),
                           lineWidth: 1)
        }
    }

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

private extension AttributedString {
    /// Return a copy with a darker, semi-transparent foreground so it
    /// can be drawn behind the main text as a stone-carved shadow.
    func transformedShadow(opacity: Double) -> AttributedString {
        var copy = self
        copy.foregroundColor = Color.black.opacity(opacity)
        return copy
    }
}

import SwiftUI

/// Arcade-launcher banner for Tokeyo Town. Rendered procedurally with
/// the same iso-prism vocabulary the game uses on its canvas so the
/// banner stays in sync with the game's visual language without
/// needing a hand-authored .matrix file.
struct TokeyoTownBanner: View {
    var body: some View {
        Canvas { context, size in
            drawSky(context: context, size: size)
            drawMountains(context: context, size: size)
            drawIsoBuildings(context: context, size: size)
            drawTitle(context: context, size: size)
        }
        .aspectRatio(128.0 / 48.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func drawSky(context: GraphicsContext, size: CGSize) {
        let top = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.55)
        let bottom = CGRect(x: 0, y: top.maxY,
                            width: size.width, height: size.height * 0.20)
        context.fill(Path(top), with: .color(Color(red: 0.96, green: 0.62, blue: 0.55)))
        context.fill(Path(bottom), with: .color(Color(red: 0.98, green: 0.82, blue: 0.55)))
        let ground = CGRect(x: 0, y: bottom.maxY,
                            width: size.width, height: size.height - bottom.maxY)
        context.fill(Path(ground), with: .color(Color(red: 0.55, green: 0.78, blue: 0.42)))
        let sunR = size.height * 0.18
        let sunRect = CGRect(x: size.width * 0.78 - sunR,
                             y: size.height * 0.42 - sunR,
                             width: sunR * 2, height: sunR * 2)
        context.fill(Path(ellipseIn: sunRect),
                     with: .color(Color(red: 0.99, green: 0.92, blue: 0.42)))
    }

    private func drawMountains(context: GraphicsContext, size: CGSize) {
        let baseY = size.height * 0.60
        for (cx, height, shade) in [
            (size.width * 0.18, size.height * 0.32, 0.62),
            (size.width * 0.38, size.height * 0.42, 0.50),
            (size.width * 0.62, size.height * 0.28, 0.68),
        ] {
            var p = Path()
            let halfW = height * 0.85
            p.move(to: CGPoint(x: cx - halfW, y: baseY))
            p.addLine(to: CGPoint(x: cx, y: baseY - height))
            p.addLine(to: CGPoint(x: cx + halfW, y: baseY))
            p.closeSubpath()
            context.fill(p, with: .color(Color(red: 0.42 * shade,
                                               green: 0.30 * shade,
                                               blue: 0.42 * shade)))
        }
    }

    private struct BuildingSpec {
        let cx: CGFloat
        let baseY: CGFloat
        let halfW: CGFloat
        let halfH: CGFloat
        let height: CGFloat
        let wall: Color
        let roof: Color
        let roofKind: RoofKind
        enum RoofKind { case gable, dome, hip }
    }

    private func drawIsoBuildings(context: GraphicsContext, size: CGSize) {
        let groundLine = size.height * 0.78
        let specs: [BuildingSpec] = [
            BuildingSpec(cx: size.width * 0.16, baseY: groundLine,
                         halfW: 9, halfH: 4.5, height: 14,
                         wall: Color(red: 0.96, green: 0.82, blue: 0.36),
                         roof: Color(red: 0.86, green: 0.26, blue: 0.24),
                         roofKind: .gable),
            BuildingSpec(cx: size.width * 0.30, baseY: groundLine + 1,
                         halfW: 7, halfH: 3.5, height: 11,
                         wall: Color(red: 0.95, green: 0.72, blue: 0.82),
                         roof: Color(red: 0.42, green: 0.62, blue: 0.85),
                         roofKind: .gable),
            BuildingSpec(cx: size.width * 0.46, baseY: groundLine,
                         halfW: 11, halfH: 5.5, height: 17,
                         wall: Color(red: 0.50, green: 0.34, blue: 0.62),
                         roof: Color(red: 0.95, green: 0.85, blue: 0.42),
                         roofKind: .dome),
            BuildingSpec(cx: size.width * 0.62, baseY: groundLine + 1,
                         halfW: 8, halfH: 4, height: 13,
                         wall: Color(red: 0.78, green: 0.55, blue: 0.42),
                         roof: Color(red: 0.30, green: 0.32, blue: 0.40),
                         roofKind: .hip),
        ]
        for spec in specs.sorted(by: { $0.cx < $1.cx }) {
            drawPrism(context: context, spec: spec)
        }
    }

    private func drawPrism(context: GraphicsContext, spec s: BuildingSpec) {
        let baseL = CGPoint(x: s.cx - s.halfW, y: s.baseY)
        let baseR = CGPoint(x: s.cx + s.halfW, y: s.baseY)
        let baseB = CGPoint(x: s.cx, y: s.baseY + s.halfH)
        let baseT = CGPoint(x: s.cx, y: s.baseY - s.halfH)
        let topL = CGPoint(x: baseL.x, y: baseL.y - s.height)
        let topR = CGPoint(x: baseR.x, y: baseR.y - s.height)
        let topB = CGPoint(x: baseB.x, y: baseB.y - s.height)
        let topT = CGPoint(x: baseT.x, y: baseT.y - s.height)

        var left = Path()
        left.move(to: baseL); left.addLine(to: baseB)
        left.addLine(to: topB); left.addLine(to: topL); left.closeSubpath()
        context.fill(left, with: .color(s.wall))

        var right = Path()
        right.move(to: baseR); right.addLine(to: baseB)
        right.addLine(to: topB); right.addLine(to: topR); right.closeSubpath()
        context.fill(right, with: .color(s.wall.adjustedTokeyo(by: 0.7)))

        var top = Path()
        top.move(to: topT); top.addLine(to: topR)
        top.addLine(to: topB); top.addLine(to: topL); top.closeSubpath()
        context.fill(top, with: .color(s.wall.adjustedTokeyo(by: 1.1)))

        switch s.roofKind {
        case .gable:
            let ridgeL = CGPoint(x: topL.x, y: topL.y - s.height * 0.5)
            let ridgeR = CGPoint(x: topR.x, y: topR.y - s.height * 0.5)
            var f1 = Path()
            f1.move(to: ridgeL); f1.addLine(to: ridgeR)
            f1.addLine(to: topR); f1.addLine(to: topT); f1.closeSubpath()
            var f2 = Path()
            f2.move(to: ridgeL); f2.addLine(to: ridgeR)
            f2.addLine(to: topB); f2.addLine(to: topL); f2.closeSubpath()
            context.fill(f2, with: .color(s.roof.adjustedTokeyo(by: 0.78)))
            context.fill(f1, with: .color(s.roof))
        case .dome:
            var dome = Path()
            dome.addArc(center: CGPoint(x: s.cx, y: topL.y),
                        radius: s.halfW,
                        startAngle: .degrees(180), endAngle: .degrees(0),
                        clockwise: false)
            dome.addLine(to: CGPoint(x: s.cx + s.halfW, y: topL.y))
            dome.addLine(to: CGPoint(x: s.cx - s.halfW, y: topL.y))
            dome.closeSubpath()
            context.fill(dome, with: .color(s.roof))
        case .hip:
            let apex = CGPoint(x: s.cx, y: topL.y - s.height * 0.6)
            for (a, b, shade) in [
                (topT, topR, 1.0),
                (topR, topB, 0.78),
                (topB, topL, 0.86),
                (topL, topT, 0.92),
            ] {
                var p = Path()
                p.move(to: apex); p.addLine(to: a); p.addLine(to: b); p.closeSubpath()
                context.fill(p, with: .color(s.roof.adjustedTokeyo(by: shade)))
            }
        }
    }

    private func drawTitle(context: GraphicsContext, size: CGSize) {
        let title = "TOKEYO TOWN"
        let font = Font.system(size: size.height * 0.28, weight: .black, design: .monospaced)
        let resolved = context.resolve(Text(title).font(font).foregroundColor(.white))
        let position = CGPoint(x: size.width * 0.84, y: size.height * 0.78)
        let measured = resolved.measure(in: CGSize(width: size.width, height: size.height))
        let pad: CGFloat = 4
        let pill = CGRect(
            x: position.x - measured.width / 2 - pad,
            y: position.y - measured.height / 2 - pad / 2,
            width: measured.width + pad * 2,
            height: measured.height + pad
        )
        context.fill(Path(roundedRect: pill, cornerRadius: 3),
                     with: .color(Color.black.opacity(0.55)))
        context.draw(resolved, at: position, anchor: .center)
    }
}

private extension Color {
    /// Multiply this color toward black (factor < 1) or toward white
    /// (factor > 1, clipped). Used to shade iso-prism faces in the
    /// banner without falling back to `.opacity()` (which is alpha
    /// rather than darkening).
    func adjustedTokeyo(by factor: Double) -> Color {
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return self }
        let f = CGFloat(factor)
        return Color(
            red: min(1, max(0, Double(rgb.redComponent * f))),
            green: min(1, max(0, Double(rgb.greenComponent * f))),
            blue: min(1, max(0, Double(rgb.blueComponent * f)))
        )
    }
}

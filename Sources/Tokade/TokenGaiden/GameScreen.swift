import SwiftUI

/// Pixel-art screen frame that wraps the whole Token Gaiden RPG view.
/// Renders as a bezeled "emulator screen" — dark outer frame with a slight
/// inner highlight, then a content area on a near-black background. A
/// global CRT post-effect (read from Notifier) overlays the whole screen
/// so every graphic — sprites, text, map, banners — gets the same
/// scanline/phosphor treatment.
struct GameScreen<Content: View>: View {
    /// Optional CRT mode applied as a full-screen overlay on the content.
    /// Pass `.off` (the default) to skip the overlay; callers normally read
    /// it from `Notifier.crtMode`.
    var crtMode: CRTMode = .off
    let content: () -> Content

    init(crtMode: CRTMode = .off, @ViewBuilder content: @escaping () -> Content) {
        self.crtMode = crtMode
        self.content = content
    }

    var body: some View {
        ZStack {
            // Outer bezel
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.13, green: 0.13, blue: 0.16))
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black, lineWidth: 2)

            // Bezel inner highlight
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(red: 0.35, green: 0.35, blue: 0.40), lineWidth: 1)
                .padding(4)

            // Screen content area, with CRT overlay applied on top of everything.
            VStack(spacing: 0) {
                content()
            }
            .padding(10)
            .background(Color(red: 0.06, green: 0.06, blue: 0.08))
            .overlay(CRTOverlay(mode: crtMode).allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(6)
        }
    }
}

/// Full-screen CRT post-effect overlay. Renders thin horizontal stripes,
/// dot grids, or vignettes on top of whatever is below — so the look
/// applies uniformly to text, sprites, the map, the launcher banner, etc.
struct CRTOverlay: View {
    let mode: CRTMode

    var body: some View {
        switch mode {
        case .off:
            Color.clear
        case .scanlines:
            stripes(spacing: 3, lineHeight: 1, color: Color.black.opacity(0.32))
        case .phosphor:
            ZStack {
                stripes(spacing: 2, lineHeight: 1, color: Color.black.opacity(0.22))
                verticalMesh(spacing: 3, color: Color.black.opacity(0.10))
            }
        case .soft:
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.30)],
                center: .center,
                startRadius: 60,
                endRadius: 480
            )
        case .dotMatrix:
            dotGrid(spacing: 3, dotSize: 1, color: Color.black.opacity(0.30))
        case .fade:
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.45)],
                center: .center,
                startRadius: 30,
                endRadius: 520
            )
        }
    }

    private func stripes(spacing: CGFloat, lineHeight: CGFloat, color: Color) -> some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                let rect = CGRect(x: 0, y: y, width: size.width, height: lineHeight)
                ctx.fill(Path(rect), with: .color(color))
                y += spacing
            }
        }
    }

    private func verticalMesh(spacing: CGFloat, color: Color) -> some View {
        Canvas { ctx, size in
            var x: CGFloat = 0
            while x < size.width {
                let rect = CGRect(x: x, y: 0, width: 1, height: size.height)
                ctx.fill(Path(rect), with: .color(color))
                x += spacing
            }
        }
    }

    private func dotGrid(spacing: CGFloat, dotSize: CGFloat, color: Color) -> some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                    ctx.fill(Path(rect), with: .color(color))
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

/// One pixel-art icon button used in the in-screen bottom menu. Highlights
/// when selected; plain otherwise.
struct PixelIconButton: View {
    let glyph: String
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack {
                    Rectangle()
                        .fill(selected ? Color(red: 0.28, green: 0.40, blue: 0.65)
                                       : Color(red: 0.18, green: 0.18, blue: 0.22))
                    Rectangle()
                        .stroke(Color.black, lineWidth: 1)
                    Rectangle()
                        .stroke(selected ? Color.white.opacity(0.6)
                                         : Color.white.opacity(0.15), lineWidth: 1)
                        .padding(1)
                    Text(glyph).font(.system(size: 18))
                }
                .frame(width: 38, height: 32)
                Text(label)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(selected ? Color.white : Color.gray)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Text-label button rendered in the pixel-art idiom — bevelled fill,
/// hard 1px outline, monospaced label. Replaces `.buttonStyle(.bordered)`
/// in the game UI so every clickable element has the same look.
struct PixelButton: View {
    let label: String
    var size: ControlSize = .small
    var prominent: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: fontSize, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(disabled ? Color.gray
                                : (prominent ? Color.white
                                             : Color(red: 0.95, green: 0.90, blue: 0.55)))
                .padding(.horizontal, hPad)
                .padding(.vertical, vPad)
                .background(
                    ZStack {
                        Rectangle()
                            .fill(prominent
                                  ? Color(red: 0.28, green: 0.40, blue: 0.65)
                                  : Color(red: 0.18, green: 0.18, blue: 0.22))
                        Rectangle().stroke(Color.black, lineWidth: 1)
                        Rectangle().stroke(Color.white.opacity(0.15), lineWidth: 1).padding(1)
                    }
                )
                .opacity(disabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var fontSize: CGFloat {
        switch size {
        case .mini, .small: return 10
        case .regular:      return 11
        case .large, .extraLarge: return 13
        @unknown default:   return 10
        }
    }
    private var hPad: CGFloat {
        switch size {
        case .mini:  return 4
        case .small: return 6
        case .regular: return 8
        case .large, .extraLarge: return 12
        @unknown default: return 6
        }
    }
    private var vPad: CGFloat {
        switch size {
        case .mini:  return 2
        case .small: return 3
        case .regular: return 4
        case .large, .extraLarge: return 6
        @unknown default: return 3
        }
    }
}

/// Pixel-art arrow button used for carousels and pagination. The glyph is
/// a Unicode triangle (◀ / ▶ / ▲ / ▼) so it renders crisply in the
/// monospaced font without any SF-symbol smoothness.
struct PixelArrowButton: View {
    enum Direction { case left, right, up, down
        var glyph: String {
            switch self {
            case .left: return "◀"
            case .right: return "▶"
            case .up: return "▲"
            case .down: return "▼"
            }
        }
    }
    let direction: Direction
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        PixelButton(label: direction.glyph, size: .small, disabled: disabled, action: action)
    }
}

/// Convenience: monospaced font matched to common semantic sizes used in
/// the game. Use in place of `.font(.caption)` etc. so everything inside
/// the GameScreen renders with the same pixel-art typography.
extension View {
    func gameFont(_ size: GameFontSize) -> some View {
        self.font(.system(size: size.points, design: .monospaced))
    }
}

enum GameFontSize {
    case xsmall, small, body, headline, title
    var points: CGFloat {
        switch self {
        case .xsmall:   return 9
        case .small:    return 10
        case .body:     return 11
        case .headline: return 13
        case .title:    return 16
        }
    }
}

/// Pixel-style framed panel used inside the screen for content blocks.
struct PixelPanel<Content: View>: View {
    let title: String?
    let content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(Color(red: 0.95, green: 0.90, blue: 0.55))
            }
            ZStack {
                Rectangle()
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.14))
                Rectangle()
                    .stroke(Color(red: 0.40, green: 0.40, blue: 0.45), lineWidth: 1)
                content()
                    .padding(8)
            }
        }
    }
}

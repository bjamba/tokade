import SwiftUI

/// All-time activity heatmap (weekday × hour). Data is unfiltered by range
/// because the value of this view is showing your *patterns* over a long span.
struct HeatmapCard: View {
    let events: [UsageEvent]
    @State private var hovered: HoveredCell?
    @State private var cursorPosition: CGPoint = .zero
    @State private var containerSize: CGSize = .zero
    @State private var tooltipSize: CGSize = .zero

    private struct HoveredCell: Equatable {
        let day: Int
        let hour: Int
        let tokens: Int
    }

    private struct HeatCell: Identifiable {
        let id = UUID()
        let weekday: Int
        let hour: Int
        let tokens: Int
    }

    private var cells: [HeatCell] {
        let cal = Calendar.current
        var bucket: [Int: [Int: Int]] = [:]
        for e in events where e.model != "<synthetic>" {
            let comps = cal.dateComponents([.weekday, .hour], from: e.timestamp)
            guard let w = comps.weekday, let h = comps.hour else { continue }
            bucket[w, default: [:]][h, default: 0] += e.grandTotal
        }
        var out: [HeatCell] = []
        for w in 1...7 {
            for h in 0..<24 {
                out.append(HeatCell(weekday: w, hour: h, tokens: bucket[w]?[h] ?? 0))
            }
        }
        return out
    }

    var body: some View {
        let all = cells
        let maxV = max(1, all.map(\.tokens).max() ?? 1)
        return Card(title: "When you use Claude (weekday × hour, all-time)") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 4) {
                    Text(" ").font(.caption2).frame(width: 28)
                    HStack(spacing: 2) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(h % 3 == 0 ? "\(h)" : "")
                                .font(.caption2).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                ForEach(1...7, id: \.self) { day in
                    HStack(alignment: .center, spacing: 4) {
                        Text(Self.weekdayShort[day - 1])
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                        HStack(spacing: 2) {
                            ForEach(0..<24, id: \.self) { hour in
                                let tokens = all.first { $0.weekday == day && $0.hour == hour }?.tokens ?? 0
                                let intensity = Double(tokens) / Double(maxV)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(heatColor(intensity))
                                    .frame(height: 16)
                                    .onHover { hovering in
                                        let cell = HoveredCell(day: day, hour: hour, tokens: tokens)
                                        if hovering {
                                            hovered = cell
                                        } else if hovered == cell {
                                            hovered = nil
                                        }
                                    }
                            }
                        }
                    }
                }
                Text("Darker = more tokens. Max bucket: \(formatCount(maxV)). Spans your full Claude Code history on disk.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerSize = geo.size }
                        .onChange(of: geo.size) { _, new in containerSize = new }
                }
            )
            .onContinuousHover { phase in
                if case .active(let p) = phase { cursorPosition = p }
            }
            .overlay(alignment: .topLeading) {
                if let h = hovered {
                    let offset = tooltipOffset()
                    MiniTooltip(
                        "\(Self.weekdayShort[h.day - 1]) \(h.hour):00–\(h.hour + 1):00",
                        rows: [
                            ("Tokens", formatCount(h.tokens)),
                            ("% of peak", String(format: "%.0f%%", Double(h.tokens) / Double(maxV) * 100))
                        ]
                    )
                    .background(
                        GeometryReader { ttGeo in
                            Color.clear
                                .onAppear { tooltipSize = ttGeo.size }
                                .onChange(of: ttGeo.size) { _, new in tooltipSize = new }
                        }
                    )
                    .offset(x: offset.x, y: offset.y)
                }
            }
        }
    }

    private static let weekdayShort = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

    /// Pick a tooltip position relative to the cursor that doesn't clip
    /// the container. Default is bottom-right of cursor; flip horizontally
    /// or vertically when there's not enough room.
    private func tooltipOffset() -> CGPoint {
        let gap: CGFloat = 14
        let tt = tooltipSize == .zero ? CGSize(width: 160, height: 60) : tooltipSize
        let container = containerSize

        // Horizontal: prefer right of cursor; flip left if right would clip.
        let rightX = cursorPosition.x + gap
        let leftX = cursorPosition.x - tt.width - gap
        let x: CGFloat = {
            if rightX + tt.width <= container.width { return rightX }
            if leftX >= 0 { return leftX }
            // Both would clip — clamp to right edge.
            return max(0, container.width - tt.width)
        }()

        // Vertical: prefer below cursor; flip above if below would clip.
        let belowY = cursorPosition.y + gap
        let aboveY = cursorPosition.y - tt.height - gap
        let y: CGFloat = {
            if belowY + tt.height <= container.height { return belowY }
            if aboveY >= 0 { return aboveY }
            return max(0, container.height - tt.height)
        }()

        return CGPoint(x: x, y: y)
    }

    private func heatColor(_ intensity: Double) -> Color {
        if intensity <= 0 { return .gray.opacity(0.08) }
        return Color.accentColor.opacity(0.15 + intensity * 0.85)
    }
}

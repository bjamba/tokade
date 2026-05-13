import Charts
import SwiftUI

/// Per-window utilization chart on the Budget tab. Each bar = one server-anchored
/// 5-hour window; height = end-of-window utilization (%) drawn from the snapshot
/// archive. Sparse until a few cycles have been recorded.
@MainActor
struct PastWindowsBudgetCard: View {
    @Bindable var store: UsageStore
    let rangeSeconds: TimeInterval
    @State private var hoverTime: Date?

    private struct WindowEntry: Identifiable {
        let id: Date
        let start: Date
        let end: Date
        let endPct: Double        // value rendered (clamped 0–100)
        let rawPct: Double        // raw computed value (may exceed 100 for approximations)
        let isCurrent: Bool
        let isApproximate: Bool
    }

    private var windowCount: Int {
        // Number of 5h windows that fit in the requested timeframe.
        max(1, Int((rangeSeconds / (5 * 3600)).rounded(.up)))
    }

    var body: some View {
        let now = Date()
        let allEvents = store.events.filter { $0.model != "<synthetic>" }

        // Server-truth: snapshots grouped by fiveResetsAt. Within a window,
        // take max `%` (monotone non-decreasing within a window).
        var perWindow: [Date: Double] = [:]
        for s in store.snapshots {
            guard let resets = s.fiveResetsAt, let pct = s.fiveHour else { continue }
            perWindow[resets] = max(perWindow[resets] ?? 0, pct)
        }
        let currentResetsAt = effectiveFiveHourResetsAt(rateLimits: store.rateLimits, now: now)

        // Approximation cap: take the MAX of (window_tokens / window_pct × 100) across
        // every snapshot-truthed window plus the current one. Max because each estimate
        // is biased *down* when claude.ai usage is missing locally — picking the highest
        // gets us closest to the real cap.
        let fiveHourCap: Double? = {
            var estimates: [Double] = []
            if let pct = store.rateLimits?.fiveHour?.usedPercentage, pct > 0.5 {
                let cutoff = now.addingTimeInterval(-5 * 3600)
                let local = allEvents
                    .filter { $0.timestamp >= cutoff }
                    .reduce(0) { $0 + $1.grandTotal }
                if local > 0 { estimates.append(Double(local) / pct * 100) }
            }
            for (resets, pct) in perWindow where pct > 0.5 {
                let start = resets.addingTimeInterval(-5 * 3600)
                let local = allEvents
                    .filter { $0.timestamp >= start && $0.timestamp < resets }
                    .reduce(0) { $0 + $1.grandTotal }
                if local > 0 { estimates.append(Double(local) / pct * 100) }
            }
            return estimates.max()
        }()

        // Build the requested span of windows, anchored to the current resets_at.
        // Prefer server-truth from snapshots; fall back to JSONL-derived approximation.
        var allEntries: [WindowEntry] = []
        let totalWanted = windowCount
        for offset in stride(from: totalWanted - 1, through: 0, by: -1) {
            let end = currentResetsAt.addingTimeInterval(-Double(offset) * 5 * 3600)
            let start = end.addingTimeInterval(-5 * 3600)
            let isCurrent = offset == 0
            if let pct = perWindow[end] {
                allEntries.append(WindowEntry(
                    id: end, start: start, end: end,
                    endPct: min(100, pct), rawPct: pct,
                    isCurrent: isCurrent, isApproximate: false
                ))
            } else if let cap = fiveHourCap, cap > 0 {
                let upper = min(end, now)
                let tokens = allEvents
                    .filter { $0.timestamp >= start && $0.timestamp < upper }
                    .reduce(0) { $0 + $1.grandTotal }
                if tokens > 0 || isCurrent {
                    let raw = Double(tokens) / cap * 100
                    allEntries.append(WindowEntry(
                        id: end, start: start, end: end,
                        endPct: min(100, raw), rawPct: raw,
                        isCurrent: isCurrent, isApproximate: true
                    ))
                }
            }
        }
        let entries = allEntries
        let xDomain: ClosedRange<Date> = (entries.first?.start ?? now)...(entries.last?.end ?? now)
        let approxCount = entries.filter(\.isApproximate).count
        let realCount = entries.count - approxCount

        _ = entries.count <= 1 && (entries.first?.isCurrent ?? false)  // onlyInProgress (reserved for future banner)
        let yMax = max(20.0, (entries.map(\.endPct).max() ?? 0) + 5)
        let showsCap = yMax >= 100
        return Card(title: "Past 5h windows utilization") {
            HStack {
                Text("\(entries.count) windows in range")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(realCount) server · \(approxCount) approx")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if entries.isEmpty {
                Text("No data — neither snapshots nor JSONL tokens cover this range.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                chart(entries: entries, xDomain: xDomain, yMax: yMax, showsCap: showsCap)
                    .frame(height: 180)
                    .overlay(alignment: .topTrailing) {
                        Group {
                            if let h = hoverTime,
                               let item = entries.first(where: { h >= $0.start && h < $0.end }) {
                                MiniTooltip(rows: tooltipRows(item: item)).padding(6)
                            }
                        }
                        .animation(.easeInOut(duration: 0.1), value: hoverTime)
                    }
                Text(footnote(showsCap: showsCap, approxCount: approxCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    private func chart(entries: [WindowEntry], xDomain: ClosedRange<Date>, yMax: Double, showsCap: Bool) -> some View {
        Chart {
            bars(entries)
            if showsCap { cap() }
            hover()
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...yMax)
        .chartYAxis { yAxis() }
        .chartXAxis { xAxis() }
        .chartXSelection(value: $hoverTime)
    }

    @ChartContentBuilder
    private func bars(_ entries: [WindowEntry]) -> some ChartContent {
        ForEach(entries) { w in
            RectangleMark(
                xStart: .value("Start", w.start),
                xEnd: .value("End", w.end),
                yStart: .value("Bottom", 0),
                yEnd: .value("Top", w.endPct)
            )
            .foregroundStyle(w.isApproximate ? Color.gray : Color.blue)
            .opacity(w.isCurrent ? 0.45 : (w.isApproximate ? 0.55 : 0.85))
        }
    }

    @ChartContentBuilder
    private func cap() -> some ChartContent {
        RuleMark(y: .value("Cap", 100))
            .foregroundStyle(.red.opacity(0.7))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .annotation(position: .top, alignment: .trailing, spacing: 0) {
                Text("100% (cap)").font(.caption2).foregroundStyle(.red.opacity(0.85))
            }
    }

    @ChartContentBuilder
    private func hover() -> some ChartContent {
        if let hoverTime {
            RuleMark(x: .value("hover", hoverTime))
                .foregroundStyle(.gray.opacity(0.4))
                .zIndex(-1)
        }
    }

    @AxisContentBuilder
    private func yAxis() -> some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine()
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(String(format: "%.0f%%", v)).font(.caption2)
                }
            }
        }
    }

    @AxisContentBuilder
    private func xAxis() -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                .font(.caption2)
        }
    }

    private func tooltipRows(item: WindowEntry) -> [(String, String)] {
        let f = Self.dateTimeFmt
        let range = "\(f.string(from: item.start))–\(f.string(from: item.end))"
        let label = item.isCurrent
            ? "Window (in progress)"
            : (item.isApproximate ? "Window (≈ approx)" : "Window")
        var rows: [(String, String)] = [
            (label, range),
            ("End %", String(format: "%.0f%%", item.endPct))
        ]
        if item.rawPct > 100.5 {
            rows.append(("Raw approx", String(format: "%.0f%% (clamped to 100%%)", item.rawPct)))
        }
        return rows
    }

    private func footnote(showsCap: Bool, approxCount: Int) -> String {
        var parts: [String] = []
        parts.append("Indigo = server-truth; gray = approximated from local Claude Code tokens.")
        if approxCount > 0 {
            parts.append("Approximations use today's derived 5h cap; expect drift if your model mix or claude.ai-vs-Code split has shifted historically. Real bars replace approximate ones as snapshots accumulate.")
        }
        if !showsCap {
            parts.append("Y is auto-scaled — usage is well below the 100% cap, which would render off-chart.")
        }
        return parts.joined(separator: " ")
    }

    private static let dateTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, h a"; return f
    }()
}

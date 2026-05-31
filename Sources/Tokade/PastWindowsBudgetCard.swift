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

    /// Computes the ordered window-end boundaries for the chart, from newest to
    /// oldest (index 0 = in-progress window).
    ///
    /// Naively, each end is `currentResetsAt - offset * 5h`. But after a window
    /// rolls over with no fresh statusline write, `effectiveFiveHourResetsAt`
    /// projects `currentResetsAt` *forward* by whole 5h cycles, while the
    /// snapshots already on disk are keyed on the *old* server `fiveResetsAt`.
    /// The projected boundaries then drift off the recorded ones by up to a few
    /// minutes (server windows aren't perfectly 5h-aligned to each other), so
    /// `perWindow[end]` misses and a server-truth bar silently degrades to an
    /// approximation — or worse, lands in the wrong slot.
    ///
    /// Fix: for every projected boundary, snap it to a recorded `fiveResetsAt`
    /// when one falls within `tolerance`. That re-anchors each completed window
    /// on the reset-time its snapshots actually belong to, independent of
    /// statusline timing. Windows with no recorded snapshot keep the projected
    /// boundary (and fall through to approximation downstream as before).
    ///
    /// Pure on its inputs so it can be unit-tested without a `UsageStore`.
    /// `nonisolated` because it touches no view state — lets tests call it
    /// synchronously despite the enclosing `@MainActor` view.
    nonisolated static func windowEnds(
        currentResetsAt: Date,
        recordedResets: [Date],
        windowCount: Int,
        tolerance: TimeInterval = 30 * 60
    ) -> [Date] {
        let sortedRecorded = recordedResets.sorted()
        var ends: [Date] = []
        for offset in 0 ..< windowCount {
            let projected = currentResetsAt.addingTimeInterval(-Double(offset) * 5 * 3600)
            // Snap to the nearest recorded reset within tolerance, if any. This
            // is what makes the server bar align to the window its snapshots
            // were keyed under, even when the projection has drifted.
            let snapped = sortedRecorded
                .filter { abs($0.timeIntervalSince(projected)) <= tolerance }
                .min(by: { abs($0.timeIntervalSince(projected)) < abs($1.timeIntervalSince(projected)) })
            ends.append(snapped ?? projected)
        }
        return ends
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

        // Build the requested span of windows. Boundaries are anchored on the
        // recorded snapshot reset-times where they exist (see `windowEnds`), so a
        // server-truth bar lands in the window its snapshots actually belong to
        // even when the projected `currentResetsAt` has drifted past a rollover.
        // Prefer server-truth from snapshots; fall back to JSONL approximation.
        var allEntries: [WindowEntry] = []
        let totalWanted = windowCount
        let ends = Self.windowEnds(
            currentResetsAt: currentResetsAt,
            recordedResets: Array(perWindow.keys),
            windowCount: totalWanted
        )
        for offset in stride(from: totalWanted - 1, through: 0, by: -1) {
            let end = ends[offset]
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
            .accessibilityLabel(accessibilityLabel(for: w))
            .accessibilityValue(String(format: "%.0f percent", w.endPct))
        }
    }

    private func accessibilityLabel(for w: WindowEntry) -> String {
        let f = Self.dateTimeFmt
        let range = "\(f.string(from: w.start)) to \(f.string(from: w.end))"
        if w.isCurrent { return "Current 5 hour window, \(range)" }
        if w.isApproximate { return "Approximate window, \(range)" }
        return "Window, \(range)"
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

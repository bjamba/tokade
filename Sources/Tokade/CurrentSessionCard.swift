import SwiftUI
import Charts

/// Budget-scoped window card. Plots `%` utilization over the current
/// server-anchored 5-hour window using the snapshot archive — model-mix
/// agnostic, weight-change-proof.
@MainActor
struct CurrentSessionCard: View {
    @Bindable var store: UsageStore
    @State private var hoverTime: Date?

    private struct Point: Identifiable {
        let id = UUID()
        let time: Date
        let pct: Double
    }

    private struct ProjPoint: Identifiable {
        let id = UUID()
        let time: Date
        let low: Double
        let high: Double
    }

    var body: some View {
        let now = Date()
        let stale = isFiveHourDataStale(rateLimits: store.rateLimits, now: now)
        let resetsAt = effectiveFiveHourResetsAt(rateLimits: store.rateLimits, now: now)
        let windowStart = resetsAt.addingTimeInterval(-5 * 3600)
        let windowEnd = resetsAt
        // If we're in a projected new window, server `%` is for the old window — treat as 0.
        let currentPct = stale ? 0.0 : (store.rateLimits?.fiveHour?.usedPercentage ?? 0)

        let points = buildPoints(snapshots: store.snapshots,
                                 resetsAt: resetsAt,
                                 windowStart: windowStart,
                                 now: now,
                                 currentPct: currentPct)
        let projection = buildProjection(points: points,
                                         currentPct: currentPct,
                                         now: now,
                                         windowEnd: windowEnd)

        return Card(title: "Current 5h budget") {
            if stale {
                Text("Window appears to have reset. Send any Claude Code message to confirm the new server %.")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "%.0f%%", currentPct))
                        .font(.title3).fontWeight(.semibold).monospacedDigit()
                    Text(stale ? "of 5h budget (projected)" : "of 5h budget")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("Resets \(Self.timeFmt.string(from: resetsAt))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("\(points.count) snapshots in window")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let projEnd = projection.last {
                        Divider().padding(.vertical, 2)
                        Text("Projected end of window")
                            .font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                        Text(projEnd.low == projEnd.high
                             ? String(format: "%.0f%%", projEnd.low)
                             : String(format: "%.0f%% – %.0f%%", projEnd.low, projEnd.high))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 130, alignment: .leading)

                chart(points: points, projection: projection,
                      windowStart: windowStart, windowEnd: windowEnd, now: now)
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .overlay(alignment: .topTrailing) {
                        if let h = hoverTime {
                            tooltip(at: h, points: points, projection: projection,
                                    windowStart: windowStart, windowEnd: windowEnd,
                                    now: now, currentPct: currentPct)
                                .padding(6)
                        }
                    }
                    .animation(.easeInOut(duration: 0.1), value: hoverTime)
            }
        }
    }

    private func chart(points: [Point], projection: [ProjPoint],
                       windowStart: Date, windowEnd: Date, now: Date) -> some View {
        Chart {
            actualSeries(points)
            projectionWedge(projection)
            paceLine(windowStart: windowStart, windowEnd: windowEnd)
            nowMark(now)
            hoverMark()
        }
        .chartXScale(domain: windowStart...windowEnd)
        .chartYScale(domain: 0...max(100.0, (points.map(\.pct).max() ?? 0) + 5))
        .chartYAxis { yAxis() }
        .chartXAxis { xAxis() }
        .chartXSelection(value: $hoverTime)
    }

    @ChartContentBuilder
    private func actualSeries(_ points: [Point]) -> some ChartContent {
        ForEach(points) { p in
            LineMark(x: .value("t", p.time), y: .value("Pct", p.pct))
                .foregroundStyle(.blue)
                .interpolationMethod(.stepEnd)
            AreaMark(x: .value("t", p.time), y: .value("Pct", p.pct))
                .foregroundStyle(.blue.opacity(0.15))
                .interpolationMethod(.stepEnd)
        }
    }

    @ChartContentBuilder
    private func projectionWedge(_ projection: [ProjPoint]) -> some ChartContent {
        ForEach(projection) { p in
            AreaMark(
                x: .value("t", p.time),
                yStart: .value("Low", p.low),
                yEnd: .value("High", p.high)
            )
            .foregroundStyle(.gray.opacity(0.18))
        }
        ForEach(projection) { p in
            LineMark(x: .value("t", p.time), y: .value("Low", p.low),
                     series: .value("Series", "Low"))
                .foregroundStyle(.gray.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        ForEach(projection) { p in
            LineMark(x: .value("t", p.time), y: .value("High", p.high),
                     series: .value("Series", "High"))
                .foregroundStyle(.gray.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    @ChartContentBuilder
    private func paceLine(windowStart: Date, windowEnd: Date) -> some ChartContent {
        LineMark(x: .value("t", windowStart), y: .value("Pct", 0.0),
                 series: .value("Series", "Pace"))
            .foregroundStyle(.red.opacity(0.7))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
        LineMark(x: .value("t", windowEnd), y: .value("Pct", 100.0),
                 series: .value("Series", "Pace"))
            .foregroundStyle(.red.opacity(0.7))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
            .annotation(position: .top, alignment: .trailing, spacing: 0) {
                Text("on-pace").font(.caption2).foregroundStyle(.red.opacity(0.85))
            }
    }

    @ChartContentBuilder
    private func nowMark(_ now: Date) -> some ChartContent {
        RuleMark(x: .value("Now", now))
            .foregroundStyle(.secondary.opacity(0.4))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .annotation(position: .top, alignment: .leading, spacing: 0) {
                Text("now").font(.caption2).foregroundStyle(.secondary)
            }
    }

    @ChartContentBuilder
    private func hoverMark() -> some ChartContent {
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
        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.hour().minute()).font(.caption2)
        }
    }

    private func buildPoints(snapshots: [UsageSnapshot], resetsAt: Date,
                             windowStart: Date, now: Date, currentPct: Double) -> [Point] {
        let inWindow = snapshots.filter {
            guard let _ = $0.fiveHour, let resets = $0.fiveResetsAt else { return false }
            // Match by resets_at to ensure same window.
            return abs(resets.timeIntervalSince(resetsAt)) < 90 &&
                   $0.t >= windowStart && $0.t <= now
        }
        var pts: [Point] = inWindow.map { Point(time: $0.t, pct: $0.fiveHour ?? 0) }
        // Anchor the line at windowStart, 0% if we don't already have an early sample.
        if pts.first?.time ?? .distantFuture > windowStart.addingTimeInterval(60) {
            pts.insert(Point(time: windowStart, pct: 0), at: 0)
        }
        // Extend the line to "now" with the current %.
        if pts.last?.time ?? .distantPast < now.addingTimeInterval(-30) {
            pts.append(Point(time: now, pct: currentPct))
        }
        return pts
    }

    /// Linear-rate projection wedge from "now" → windowEnd in %-units.
    /// Low = average pace from windowStart → now; High = recent (last hour) pace.
    private func buildProjection(points: [Point],
                                 currentPct: Double,
                                 now: Date,
                                 windowEnd: Date) -> [ProjPoint] {
        guard let first = points.first else { return [] }
        let elapsedSec = max(60.0, now.timeIntervalSince(first.time))
        let avgRate = (currentPct - first.pct) / elapsedSec  // pct per second

        let recentCutoff = now.addingTimeInterval(-60 * 60)
        let recentAnchor = points.last(where: { $0.time <= recentCutoff }) ?? first
        let recentSec = max(60.0, now.timeIntervalSince(recentAnchor.time))
        let recentRate = (currentPct - recentAnchor.pct) / recentSec

        let lowRate = min(avgRate, recentRate)
        let highRate = max(avgRate, recentRate)
        let secsLeft = max(0, windowEnd.timeIntervalSince(now))
        let endLow = max(currentPct, currentPct + lowRate * secsLeft)
        let endHigh = max(currentPct, currentPct + highRate * secsLeft)

        return [
            ProjPoint(time: now, low: currentPct, high: currentPct),
            ProjPoint(time: windowEnd, low: endLow, high: endHigh)
        ]
    }

    private func tooltip(at hover: Date, points: [Point], projection: [ProjPoint],
                         windowStart: Date, windowEnd: Date, now: Date,
                         currentPct: Double) -> some View {
        let rows = tooltipRows(at: hover, points: points, projection: projection,
                               windowStart: windowStart, windowEnd: windowEnd,
                               now: now, currentPct: currentPct)
        return MiniTooltip(Self.timeFmt.string(from: hover), rows: rows)
    }

    private func tooltipRows(at hover: Date, points: [Point], projection: [ProjPoint],
                             windowStart: Date, windowEnd: Date, now: Date,
                             currentPct: Double) -> [(String, String)] {
        let totalSec = max(1, windowEnd.timeIntervalSince(windowStart))
        let progress = max(0, min(1, hover.timeIntervalSince(windowStart) / totalSec))
        let pacePct = progress * 100

        var rows: [(String, String)] = []
        if hover <= now {
            let actual = points.last(where: { $0.time <= hover })?.pct ?? 0
            rows.append(("Actual", String(format: "%.1f%%", actual)))
        } else if let last = projection.last {
            let secAfterNow = hover.timeIntervalSince(now)
            let totalForward = max(1, windowEnd.timeIntervalSince(now))
            let frac = max(0, min(1, secAfterNow / totalForward))
            let low = currentPct + (last.low - currentPct) * frac
            let high = currentPct + (last.high - currentPct) * frac
            if low == high {
                rows.append(("Projected", String(format: "%.0f%%", low)))
            } else {
                rows.append(("Projected", String(format: "%.0f%% – %.0f%%", low, high)))
            }
        }
        rows.append(("Pace", String(format: "%.0f%%", pacePct)))
        return rows
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
}

import Charts
import SwiftUI

@MainActor
struct YTDCumulativeCard: View {
    @Bindable var store: UsageStore
    @State private var hoverDate: Date?

    var body: some View {
        let cal = Calendar.current
        let yearStart = cal.dateInterval(of: .year, for: Date())?.start ?? Date()
        let yearEnd = cal.date(byAdding: .year, value: 1, to: yearStart) ?? Date()
        let now = Date()

        let ytd = store.events
            .filter { $0.timestamp >= yearStart && $0.model != "<synthetic>" }
            .sorted { $0.timestamp < $1.timestamp }

        var dailyTotal: [Date: Int] = [:]
        for e in ytd {
            let d = cal.startOfDay(for: e.timestamp)
            dailyTotal[d, default: 0] += e.grandTotal
        }
        var cum = 0
        var cumPoints: [(Date, Int)] = []
        for day in dailyTotal.keys.sorted() {
            cum += dailyTotal[day] ?? 0
            cumPoints.append((day, cum))
        }

        let elapsedDays = max(1, cal.dateComponents([.day], from: yearStart, to: now).day ?? 1)
        let totalDays = cal.dateComponents([.day], from: yearStart, to: yearEnd).day ?? 365
        let remainingDays = max(0, totalDays - elapsedDays)

        let ytdRate = Double(cum) / Double(elapsedDays)
        let last30Cutoff = cal.date(byAdding: .day, value: -30, to: now) ?? yearStart
        let last30Total = ytd
            .filter { $0.timestamp >= last30Cutoff }
            .reduce(0) { $0 + $1.grandTotal }
        let last30Days = min(30, elapsedDays)
        let last30Rate = Double(last30Total) / Double(max(1, last30Days))

        let lowRate = min(ytdRate, last30Rate)
        let highRate = max(ytdRate, last30Rate)
        let projectedLow = cum + Int(lowRate * Double(remainingDays))
        let projectedHigh = cum + Int(highRate * Double(remainingDays))

        return Card(title: "YTD cumulative + projection") {
            if cumPoints.isEmpty {
                Text("No usage YTD.").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(cumPoints, id: \.0) { p in
                        LineMark(x: .value("Date", p.0), y: .value("Tokens", p.1),
                                 series: .value("Series", "Actual"))
                            .foregroundStyle(.blue)
                        AreaMark(x: .value("Date", p.0), y: .value("Tokens", p.1))
                            .foregroundStyle(.blue.opacity(0.12))
                    }
                    AreaMark(x: .value("Date", now),
                             yStart: .value("Low", cum),
                             yEnd: .value("High", cum))
                        .foregroundStyle(.gray.opacity(0.18))
                    AreaMark(x: .value("Date", yearEnd),
                             yStart: .value("Low", projectedLow),
                             yEnd: .value("High", projectedHigh))
                        .foregroundStyle(.gray.opacity(0.18))
                    LineMark(x: .value("Date", now), y: .value("Tokens", cum),
                             series: .value("Series", "Damped"))
                        .foregroundStyle(.gray.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    LineMark(x: .value("Date", yearEnd), y: .value("Tokens", projectedLow),
                             series: .value("Series", "Damped"))
                        .foregroundStyle(.gray.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    LineMark(x: .value("Date", now), y: .value("Tokens", cum),
                             series: .value("Series", "Responsive"))
                        .foregroundStyle(.gray.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    LineMark(x: .value("Date", yearEnd), y: .value("Tokens", projectedHigh),
                             series: .value("Series", "Responsive"))
                        .foregroundStyle(.gray.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                .chartXScale(domain: yearStart...yearEnd)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatCount(Int(v))).font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.caption2)
                    }
                }
                .frame(height: 200)
                .chartXSelection(value: $hoverDate)
                .overlay(alignment: .topTrailing) {
                    Group {
                        if let h = hoverDate {
                            ytdTooltip(at: h, cumPoints: cumPoints,
                                       cum: cum, ytdRate: ytdRate, last30Rate: last30Rate,
                                       totalDays: totalDays, yearStart: yearStart,
                                       projectedLow: projectedLow, projectedHigh: projectedHigh,
                                       now: now, yearEnd: yearEnd)
                                .padding(6)
                        }
                    }
                    .animation(.easeInOut(duration: 0.1), value: hoverDate)
                }
                HStack(spacing: 16) {
                    chip(formatCount(cum), "YTD")
                    chip("\(formatCount(projectedLow)) – \(formatCount(projectedHigh))", "EOY range")
                    chip(formatCount(Int(ytdRate)), "YTD daily")
                    chip(formatCount(Int(last30Rate)), "30d daily")
                }
                .padding(.top, 4)
                Text("Wedge spans YTD-average rate (damped) and last-30-day rate (responsive).")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chip(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.caption).fontWeight(.semibold).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func ytdTooltip(at hover: Date,
                            cumPoints: [(Date, Int)],
                            cum: Int,
                            ytdRate: Double,
                            last30Rate: Double,
                            totalDays: Int,
                            yearStart: Date,
                            projectedLow: Int,
                            projectedHigh: Int,
                            now: Date,
                            yearEnd: Date) -> some View {
        let cal = Calendar.current
        var rows: [(String, String)] = [("Date", Self.dayFmt.string(from: hover))]
        if hover <= now {
            let actual = cumPoints.last(where: { $0.0 <= hover })?.1
                ?? cumPoints.first?.1 ?? 0
            rows.append(("Cumulative", formatCount(actual)))
        } else if hover <= yearEnd {
            // Linearly interpolate the projection wedge between (now, cum)
            // and (yearEnd, low/high).
            let totalForward = max(1, yearEnd.timeIntervalSince(now))
            let frac = max(0, min(1, hover.timeIntervalSince(now) / totalForward))
            let low = cum + Int(Double(projectedLow - cum) * frac)
            let high = cum + Int(Double(projectedHigh - cum) * frac)
            if low == high {
                rows.append(("Projected", formatCount(low)))
            } else {
                rows.append(("Projected", "\(formatCount(low)) – \(formatCount(high))"))
            }
        }
        let elapsed = max(1, cal.dateComponents([.day], from: yearStart, to: hover).day ?? 1)
        let pace = Double(cum) / Double(max(1, elapsed)) * Double(totalDays)
        rows.append(("YTD-rate pace → EOY", formatCount(Int(pace))))
        return MiniTooltip(rows: rows)
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()
}

import Charts
import SwiftUI

@MainActor
struct ModelsTab: View {
    @Bindable var store: UsageStore
    @State private var range: TimeRange = .sevenDays
    @State private var hoverModel: String?
    @State private var hoverSlash: String?
    @State private var hoverProject: String?
    @State private var hoverTool: String?

    enum TimeRange: String, CaseIterable, Identifiable {
        case oneDay = "1d"
        case sevenDays = "7d"
        case thirtyDays = "30d"
        var id: String { rawValue }
        var seconds: TimeInterval {
            switch self {
            case .oneDay: return 24 * 3600
            case .sevenDays: return 7 * 24 * 3600
            case .thirtyDays: return 30 * 24 * 3600
            }
        }
    }

    private var events: [UsageEvent] {
        store.events.within(range.seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                HStack {
                    Picker("Range", selection: $range) {
                        ForEach(TimeRange.allCases) { r in Text(r.rawValue).tag(r) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                    summary
                }
            }
            tokensByModelCard
            slashCommandCard
            projectBreakdownCard
            toolUsageCard
        }
    }


    // MARK: Summary chips

    private var summary: some View {
        let total = events.grandTotal()
        let cacheRead = events.reduce(0) { $0 + $1.cacheReadTokens }
        let totalInput = events.reduce(0) {
            $0 + $1.inputTokens + $1.cacheCreationTokens + $1.cacheReadTokens
        }
        let cachePct = totalInput > 0 ? Double(cacheRead) / Double(totalInput) * 100 : 0

        return HStack(spacing: 10) {
            chip("\(formatCount(total))", "tokens")
            chip(String(format: "%.0f%%", cachePct), "cache")
            chip("\(Set(events.compactMap(\.sessionId)).count)", "sessions")
        }
    }

    private func chip(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.caption).fontWeight(.semibold).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Card 1 — aggregate tokens per model

    private var tokensByModelCard: some View {
        let totals = events.groupedByModel()  // already sorted by total desc
        let modelDomain = totals.map(\.model)
        let totalsDict = Dictionary(uniqueKeysWithValues: totals.map { ($0.model, $0.total) })
        let ordered = totals.map { (model: $0.model, total: $0.total) }
        let grand = totals.reduce(0) { $0 + $1.total }
        return Card(title: "Tokens by model") {
            if ordered.isEmpty {
                emptyState
            } else {
                Chart(ordered, id: \.model) { row in
                    BarMark(
                        x: .value("Tokens", row.total),
                        y: .value("Model", "\(modelGlyph(row.model)) \(row.model)"),
                        height: .fixed(12)
                    )
                    .foregroundStyle(modelColor(row.model))
                    .accessibilityLabel(row.model)
                    .accessibilityValue("\(formatCount(row.total)) tokens, \(String(format: "%.1f", grand > 0 ? Double(row.total) / Double(grand) * 100 : 0)) percent of total")
                    .annotation(position: .trailing) {
                        Text(formatCount(row.total))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartYScale(domain: modelDomain.map { "\(modelGlyph($0)) \($0)" })
                .chartXAxis(.hidden)
                .chartYSelection(value: $hoverModel)
                .frame(height: CGFloat(modelDomain.count) * 24 + 16)
                .overlay(alignment: .topTrailing) {
                    Group {
                        if let hoveredLabel = hoverModel,
                           let m = modelDomain.first(where: { hoveredLabel == "\(modelGlyph($0)) \($0)" }),
                           let t = totalsDict[m] {
                            MiniTooltip(rows: [
                                ("Model", "\(modelGlyph(m)) \(m)"),
                                ("Tokens", formatCount(t)),
                                ("Share", String(format: "%.1f%%",
                                                  grand > 0 ? Double(t) / Double(grand) * 100 : 0))
                            ]).padding(6)
                        }
                    }
                    .animation(.easeInOut(duration: 0.1), value: hoverModel)
                }
            }
        }
    }

    private static let tooltipDayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()

    // MARK: Card 2 — project breakdown

    private var projectBreakdownCard: some View {
        let totals = Array(events.groupedByProject().prefix(5))
        let categoryOrder = totals.map(\.project)
        let topNames = Set(categoryOrder)
        let stacked = events.stackedByProjectAndModel().filter { topNames.contains($0.category) }
        return Card(title: "Top 5 projects by tokens (by model)") {
            if totals.isEmpty {
                emptyState
            } else {
                stackedHorizontalChart(rows: stacked,
                                        categoryOrder: categoryOrder,
                                        height: CGFloat(totals.count) * 24 + 50,
                                        hover: $hoverProject)
                    .overlay(alignment: .topTrailing) {
                        Group {
                            stackedTooltip(rows: stacked, hover: hoverProject, label: "Project")
                        }
                        .animation(.easeInOut(duration: 0.1), value: hoverProject)
                    }
            }
        }
    }

    // MARK: Card 3 — tool usage

    private var toolUsageCard: some View {
        let totals = Array(events.toolCallCounts().prefix(5))
        let categoryOrder = totals.map(\.tool)
        let topNames = Set(categoryOrder)
        let stacked = events.stackedByToolAndModel().filter { topNames.contains($0.category) }
        return Card(title: "Top 5 tool calls (by model)") {
            if totals.isEmpty {
                emptyState
            } else {
                stackedHorizontalChart(rows: stacked,
                                        categoryOrder: categoryOrder,
                                        height: CGFloat(totals.count) * 24 + 50,
                                        hover: $hoverTool,
                                        xLabel: "Calls")
                    .overlay(alignment: .topTrailing) {
                        Group {
                            stackedTooltip(rows: stacked, hover: hoverTool, label: "Tool",
                                           valueLabel: "Calls", formatValue: { "\($0)" })
                        }
                        .animation(.easeInOut(duration: 0.1), value: hoverTool)
                    }
            }
        }
    }

    // MARK: Stacked-by-model helpers

    private func stackedHorizontalChart(rows: [StackedRow],
                                         categoryOrder: [String],
                                         height: CGFloat,
                                         hover: Binding<String?>,
                                         xLabel: String = "Tokens") -> some View {
        let modelDomain = sortedModels(Array(Set(rows.map(\.model))))
        let modelRange = modelDomain.map { modelColor($0) }
        let categoryIndex: [String: Int] = Dictionary(
            uniqueKeysWithValues: categoryOrder.enumerated().map { ($1, $0) }
        )
        let modelIndex: [String: Int] = Dictionary(
            uniqueKeysWithValues: modelDomain.enumerated().map { ($1, $0) }
        )
        let sortedRows = rows.sorted { a, b in
            let ca = categoryIndex[a.category] ?? Int.max
            let cb = categoryIndex[b.category] ?? Int.max
            if ca != cb { return ca < cb }
            let ma = modelIndex[a.model] ?? Int.max
            let mb = modelIndex[b.model] ?? Int.max
            return ma < mb
        }
        // Total per category for the trailing annotation.
        var categoryTotals: [String: Int] = [:]
        for r in rows { categoryTotals[r.category, default: 0] += r.value }

        // Prepend the tier-shape glyph to model names in the legend so
        // colorblind users have a second visual channel. Stored as a parallel
        // domain (`modelLegendDomain`) so the legend renders glyph + name
        // while underlying data still keys off the bare model id.
        let modelLegendDomain = modelDomain.map { "\(modelGlyph($0)) \($0)" }
        let glyphLookup: [String: String] = Dictionary(
            uniqueKeysWithValues: zip(modelDomain, modelLegendDomain)
        )

        return Chart {
            ForEach(sortedRows) { row in
                BarMark(
                    x: .value(xLabel, row.value),
                    y: .value("Category", row.category),
                    height: .fixed(12)
                )
                .foregroundStyle(by: .value("Model", glyphLookup[row.model] ?? row.model))
                .accessibilityLabel("\(row.category), \(row.model)")
                .accessibilityValue("\(formatCount(row.value)) \(xLabel.lowercased())")
            }
            ForEach(categoryOrder, id: \.self) { cat in
                let total = categoryTotals[cat] ?? 0
                PointMark(
                    x: .value(xLabel, total),
                    y: .value("Category", cat)
                )
                .symbolSize(0)
                .annotation(position: .trailing) {
                    Text(formatCount(total))
                        .font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                }
            }
        }
        .chartForegroundStyleScale(domain: modelLegendDomain, range: modelRange)
        .chartYScale(domain: categoryOrder)
        .chartLegend(position: .bottom, spacing: 6)
        .chartXAxis(.hidden)
        .chartYSelection(value: hover)
        .frame(height: height)
    }

    @ViewBuilder
    private func stackedTooltip(rows: [StackedRow], hover: String?, label: String,
                                 valueLabel: String = "Tokens",
                                 formatValue: ((Int) -> String)? = nil) -> some View {
        if let h = hover {
            let pieces = rows.filter { $0.category == h }.sorted { $0.value > $1.value }
            let total = pieces.reduce(0) { $0 + $1.value }
            if !pieces.isEmpty {
                MiniTooltip(rows: stackedTooltipRows(label: label, hover: h,
                                                      pieces: pieces, total: total,
                                                      valueLabel: valueLabel,
                                                      formatValue: formatValue))
                    .padding(6)
            }
        }
    }

    private func stackedTooltipRows(label: String, hover: String,
                                     pieces: [StackedRow], total: Int,
                                     valueLabel: String,
                                     formatValue: ((Int) -> String)?) -> [(String, String)] {
        let f = formatValue ?? { formatCount($0) }
        var rows: [(String, String)] = [
            (label, hover),
            (valueLabel, f(total))
        ]
        for p in pieces.prefix(4) {
            rows.append(("\(modelGlyph(p.model)) \(p.model)", f(p.value)))
        }
        return rows
    }

    // MARK: Slash commands

    private var slashCommandCard: some View {
        let result = events.groupedBySlashCommand()
        let topCmds = Array(result.commands.prefix(5))
        let categoryOrder = topCmds.map { "/\($0.name)" }
        let topNames = Set(categoryOrder)
        let stacked = events.stackedBySlashCommandAndModel().filter { topNames.contains($0.category) }
        let total = topCmds.reduce(0) { $0 + $1.total }
        return Card(title: "Top 5 slash commands by tokens (by model)") {
            if total == 0 {
                emptyState
            } else {
                stackedHorizontalChart(rows: stacked,
                                        categoryOrder: categoryOrder,
                                        height: CGFloat(topCmds.count) * 24 + 50,
                                        hover: $hoverSlash)
                    .overlay(alignment: .topTrailing) {
                        Group {
                            stackedTooltip(rows: stacked, hover: hoverSlash, label: "Command")
                        }
                        .animation(.easeInOut(duration: 0.1), value: hoverSlash)
                    }
            }
        }
    }

    private var emptyState: some View {
        Text("No data in selected range")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }
}


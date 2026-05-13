import SwiftUI
import Charts

struct WindowSkillsCard: View {
    @Bindable var store: UsageStore
    @State private var hover: String?

    var body: some View {
        let now = Date()
        let resetsAt = store.rateLimits?.fiveHour?.resetsAt ?? now.addingTimeInterval(5 * 3600)
        let windowStart = resetsAt.addingTimeInterval(-5 * 3600)
        let inWindow = store.events.filter {
            $0.timestamp >= windowStart && $0.timestamp <= now && $0.model != "<synthetic>"
        }
        let cmds = inWindow.groupedBySlashCommand().commands
        let total = cmds.reduce(0) { $0 + $1.total }

        return Card(title: "Skills used in current 5h window") {
            if cmds.isEmpty {
                Text("No slash commands invoked in this window.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                Chart(cmds, id: \.name) { row in
                    BarMark(
                        x: .value("Tokens", row.total),
                        y: .value("Command", "/\(row.name)")
                    )
                    .foregroundStyle(.purple.gradient)
                    .annotation(position: .trailing) {
                        Text(formatCount(row.total))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYSelection(value: $hover)
                .frame(height: CGFloat(cmds.count) * 24 + 16)
                .overlay(alignment: .topTrailing) {
                    if let label = hover, let row = cmds.first(where: { "/\($0.name)" == label }) {
                        MiniTooltip(rows: [
                            ("Command", "/\(row.name)"),
                            ("Tokens", formatCount(row.total)),
                            ("Share", String(format: "%.1f%%",
                                             total > 0 ? Double(row.total) / Double(total) * 100 : 0))
                        ]).padding(6)
                    }
                }
                .animation(.easeInOut(duration: 0.1), value: hover)
            }
        }
    }
}

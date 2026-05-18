import AppKit
import SwiftUI

@MainActor
struct MenuView: View {
    @Bindable var store: UsageStore
    @Bindable var gaiden: TokenGaidenStore
    @Bindable var notifier: Notifier
    @State private var tab: Tab = .budget

    enum Tab: String, CaseIterable, Identifiable {
        case budget = "Budget"
        case models = "Models"
        case trends = "Trends"
        case games  = "Games"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabPicker
            Divider()
            // Games tab manages its own layout (emulator screen + internal
            // scroll regions); the other tabs are vertical lists and want the
            // outer ScrollView. Special-casing the Games tab is what keeps
            // the bottom nav buttons from being clipped under the footer.
            Group {
                switch tab {
                case .budget:
                    ScrollView { BudgetTab(store: store).padding(16) }
                case .models:
                    ScrollView { ModelsTab(store: store).padding(16) }
                case .trends:
                    ScrollView { TrendsTab(store: store).padding(16) }
                case .games:
                    GamesTab(gaiden: gaiden, store: store, notifier: notifier)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 580, height: 660)
        .onChange(of: tab) { _, new in
            if new == .games { gaiden.acknowledgeUnseen() }
        }
    }

    private var header: some View {
        HStack {
            Image(nsImage: tokadeIcon(size: 18))
            Text("Tokade").font(.headline)
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            ForEach(Tab.allCases) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Text(store.lastUpdated.map { "Updated \(Self.timeFormatter.string(from: $0))" } ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            // Destructive actions live in nested submenus rather than
            // external confirmation dialogs — the latter steal focus from
            // MenuBarExtra's window and dismiss the whole panel. The submenu
            // requires a second deliberate click, which is the confirmation.
            Menu {
                // App-level preferences live here, not inside the game.
                // Usage alerts watch Claude API budget thresholds and 5-minute
                // token bursts — they're a Tokade concern, not a Tokegotchi
                // gameplay setting.
                Toggle("Usage alerts", isOn: Binding(
                    get: { notifier.usageAlerts },
                    set: { notifier.setUsageAlerts($0) }
                ))
                Divider()
                Menu("Reset Tokegotchi…") {
                    Button("Confirm reset (cannot be undone)", role: .destructive) {
                        Task { await gaiden.eraseHistory() }
                    }
                }
                Menu("Erase Tokade budget history…") {
                    Button("Confirm erase (cannot be undone)", role: .destructive) {
                        Task { await store.eraseHistory() }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    static let shortDateTime: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .short; return f
    }()
}

// MARK: - Budget tab

@MainActor
struct BudgetTab: View {
    @Bindable var store: UsageStore
    @State private var range: BudgetRange = .sevenDays

    enum BudgetRange: String, CaseIterable, Identifiable {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.claudeCodeMissing {
                claudeCodeMissingBanner
            }
            if let snapshot = store.rateLimits {
                rateLimitsSection(snapshot)
            } else {
                statuslineHint
            }
            CurrentSessionCard(store: store)
            Card {
                HStack {
                    Picker("Range", selection: $range) {
                        ForEach(BudgetRange.allCases) { r in Text(r.rawValue).tag(r) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                    Text("range applies below")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            PastWindowsBudgetCard(store: store, rangeSeconds: range.seconds)
        }
    }

    private var claudeCodeMissingBanner: some View {
        Card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude Code not detected").font(.subheadline).fontWeight(.semibold)
                    Text("Tokade reads session logs from `~/.claude/projects/`. That directory doesn't exist on this machine. Install Claude Code and send at least one message; data will appear here on the next 30-second poll.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func rateLimitsSection(_ s: RateLimitSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subscription limits").font(.subheadline).fontWeight(.semibold)
            if let w = s.fiveHour { windowRow(label: "5 hours", window: w) }
            if let w = s.sevenDay { windowRow(label: "7 days", window: w) }
            Text("via Claude Code · captured \(MenuView.timeFormatter.string(from: s.capturedAt))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func windowRow(label: String, window: RateLimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", window.usedPercentage))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(barColor(window.usedPercentage))
            }
            ProgressView(value: min(window.usedPercentage, 100), total: 100)
                .tint(barColor(window.usedPercentage))
            Text("Resets \(MenuView.shortDateTime.string(from: window.resetsAt))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var statuslineHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No subscription data yet").font(.subheadline).fontWeight(.semibold)
            Text("Send any Claude Code message to populate the rate-limit cache.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func barColor(_ pct: Double) -> Color {
        pct < 85 ? .blue : .red
    }
}

// MARK: - Trends tab

@MainActor
struct TrendsTab: View {
    @Bindable var store: UsageStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeatmapCard(events: store.events)
            YTDCumulativeCard(store: store)
        }
    }
}

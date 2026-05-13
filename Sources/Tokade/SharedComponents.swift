import SwiftUI
import AppKit

/// Search for a resource shipped with the app. We don't use `Bundle.module`
/// because SPM's auto-generated accessor for executable targets only looks at
/// `Bundle.main.bundleURL/Tokade_Tokade.bundle` (top of the .app — wrong spot)
/// and a hard-coded build-time path that dies if the project dir is renamed
/// or the .app is run from `/Applications`.
private func appBundledResource(named name: String, ext: String) -> URL? {
    let main = Bundle.main
    let candidates: [URL?] = [
        main.resourceURL?
            .appendingPathComponent("Tokade_Tokade.bundle")
            .appendingPathComponent("\(name).\(ext)"),
        main.bundleURL
            .appendingPathComponent("Tokade_Tokade.bundle")
            .appendingPathComponent("\(name).\(ext)"),
        main.resourceURL?.appendingPathComponent("\(name).\(ext)"),
    ]
    for c in candidates {
        if let url = c, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
    }
    return nil
}

/// Load the bundled Tokade glyph as a template NSImage at the requested point size.
/// Falls back to an SF Symbol if the PNG isn't found.
func tokadeIcon(size: CGFloat = 18) -> NSImage {
    let url = appBundledResource(named: "MenuBarIcon", ext: "png")
    let img = url.flatMap(NSImage.init(contentsOf:))
        ?? NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: nil)
        ?? NSImage()
    img.size = NSSize(width: size, height: size)
    img.isTemplate = true
    return img
}

struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.subheadline).fontWeight(.semibold)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}

enum ModelTier: Int {
    case haiku = 0, sonnet = 1, opus = 2, other = 3
    /// All in the blue family. Tier separation comes primarily from
    /// brightness + saturation (light → dark, low → high), with a tiny
    /// hue shift around system-blue (~0.60) for a second distinction axis.
    var hue: Double {
        switch self {
        case .haiku: return 0.50   // cyan / blue-green
        case .sonnet: return 0.56  // blue with cyan tint
        case .opus: return 0.60    // pure blue (matches system .blue)
        case .other: return 0.0
        }
    }
    var baseSaturation: Double {
        switch self {
        case .haiku: return 0.42
        case .sonnet: return 0.55
        case .opus: return 0.68
        case .other: return 0.45
        }
    }
    var baseBrightness: Double {
        switch self {
        case .haiku: return 0.92
        case .sonnet: return 0.80
        case .opus: return 0.62
        case .other: return 0.78
        }
    }
}

/// Parse a model name into (tier, major, minor). Returns ((Haiku|Sonnet|Opus|other), v.major, v.minor).
/// Unknown formats land in `.other` at version (0,0).
func modelRank(_ name: String) -> (tier: ModelTier, major: Int, minor: Int) {
    let lower = name.lowercased()
    let tier: ModelTier
    if lower.contains("haiku") { tier = .haiku }
    else if lower.contains("sonnet") { tier = .sonnet }
    else if lower.contains("opus") { tier = .opus }
    else { tier = .other }

    let parts = lower.components(separatedBy: CharacterSet.decimalDigits.inverted)
        .compactMap { Int($0) }
    let major = parts.first ?? 0
    let minor = parts.dropFirst().first ?? 0
    return (tier, major, minor)
}

/// Sort: Haiku → Sonnet → Opus, then by major.minor ascending.
func sortedModels(_ models: [String]) -> [String] {
    models.sorted { a, b in
        let ra = modelRank(a), rb = modelRank(b)
        if ra.tier.rawValue != rb.tier.rawValue { return ra.tier.rawValue < rb.tier.rawValue }
        if ra.major != rb.major { return ra.major < rb.major }
        if ra.minor != rb.minor { return ra.minor < rb.minor }
        return a < b
    }
}

/// Returns the current 5-hour window's effective `resetsAt`. If the server-reported
/// `resetsAt` is in the past (because no Claude Code message has fired since the
/// window rolled over), advance forward by exact 5-hour cycles. Falls back to a
/// near-future default if no server data exists at all.
func effectiveFiveHourResetsAt(rateLimits: RateLimitSnapshot?, now: Date = Date()) -> Date {
    guard let server = rateLimits?.fiveHour?.resetsAt else {
        return now.addingTimeInterval(5 * 3600)
    }
    if now <= server { return server }
    let elapsed = now.timeIntervalSince(server)
    let cyclesPassed = Int((elapsed / (5 * 3600)).rounded(.down)) + 1
    return server.addingTimeInterval(Double(cyclesPassed) * 5 * 3600)
}

/// True iff the server's last reported 5-hour `resetsAt` is already in the past.
func isFiveHourDataStale(rateLimits: RateLimitSnapshot?, now: Date = Date()) -> Bool {
    guard let server = rateLimits?.fiveHour?.resetsAt else { return false }
    return now > server
}

/// Deterministic per-model color. Whole palette sits in the blue family; tiers
/// separate by brightness (Haiku light → Sonnet mid → Opus dark) plus a slight
/// hue shift. Minor-version steps nudge brightness so multiple versions in the
/// same tier (e.g. Opus 4-6 vs 4-7) are still distinguishable.
func modelColor(_ model: String) -> Color {
    let r = modelRank(model)
    if r.tier == .other {
        var hasher = Hasher()
        hasher.combine(model)
        let h = abs(hasher.finalize()) % 360
        return Color(hue: Double(h) / 360.0, saturation: 0.55, brightness: 0.80)
    }
    // Within-tier minor-version offset (newer minor → brighter), small enough
    // not to cross tier boundaries.
    let intraOffset = Double(r.minor - 5) * 0.035
    let brightness = max(0.45, min(0.95, r.tier.baseBrightness + intraOffset))
    // Slight transparency lets the panel material show through so the bars
    // read softer rather than as solid heavy fills.
    return Color(hue: r.tier.hue,
                 saturation: r.tier.baseSaturation,
                 brightness: brightness)
        .opacity(0.92)
}

struct MiniTooltip: View {
    let title: String?
    let rows: [(label: String, value: String)]

    init(_ title: String? = nil, rows: [(String, String)]) {
        self.title = title
        self.rows = rows
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
            if let title {
                GridRow {
                    Text(title).font(.caption2).fontWeight(.semibold).gridCellColumns(2)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.label).font(.caption2).foregroundStyle(.secondary)
                    Text(row.value).font(.system(.caption2, design: .monospaced))
                        .gridColumnAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary, lineWidth: 0.5))
        .allowsHitTesting(false)  // tooltip never absorbs hover/click events
    }
}


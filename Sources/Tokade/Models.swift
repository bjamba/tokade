import Foundation

struct UsageEvent: Hashable {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let sessionId: String?
    let messageId: String?
    let cwd: String?
    let tools: [String]
    let slashCommand: String?

    var grandTotal: Int {
        inputTokens + cacheCreationTokens + cacheReadTokens + outputTokens
    }
}

extension Sequence where Element == UsageEvent {
    func within(_ interval: TimeInterval, of now: Date = Date()) -> [UsageEvent] {
        let cutoff = now.addingTimeInterval(-interval)
        return filter { $0.timestamp >= cutoff }
    }

    func grandTotal() -> Int {
        reduce(0) { $0 + $1.grandTotal }
    }

    func excludingSynthetic() -> [UsageEvent] {
        filter { $0.model != "<synthetic>" }
    }

    func groupedByModel() -> [(model: String, total: Int)] {
        var d: [String: Int] = [:]
        for e in self where e.model != "<synthetic>" {
            d[e.model, default: 0] += e.grandTotal
        }
        return d.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    func groupedByProject() -> [(project: String, total: Int)] {
        var d: [String: Int] = [:]
        for e in self {
            let p = e.cwd.flatMap { (URL(fileURLWithPath: $0)).lastPathComponent } ?? "—"
            d[p, default: 0] += e.grandTotal
        }
        return d.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    func toolCallCounts() -> [(tool: String, count: Int)] {
        var d: [String: Int] = [:]
        for e in self { for t in e.tools { d[t, default: 0] += 1 } }
        return d.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    func groupedBySlashCommand() -> (commands: [(name: String, total: Int)], noCommand: Int) {
        var perCmd: [String: Int] = [:]
        var noCmd = 0
        for e in self where e.model != "<synthetic>" {
            if let cmd = e.slashCommand {
                perCmd[cmd, default: 0] += e.grandTotal
            } else {
                noCmd += e.grandTotal
            }
        }
        let sorted = perCmd.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
        return (sorted, noCmd)
    }

    func stackedByProjectAndModel() -> [StackedRow] {
        var d: [String: [String: Int]] = [:]
        for e in self where e.model != "<synthetic>" {
            let p = e.cwd.flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? "—"
            d[p, default: [:]][e.model, default: 0] += e.grandTotal
        }
        return d.flatMap { (proj, models) in
            models.map { StackedRow(category: proj, model: $0.key, value: $0.value) }
        }
    }

    func stackedBySlashCommandAndModel() -> [StackedRow] {
        var d: [String: [String: Int]] = [:]
        for e in self where e.model != "<synthetic>" {
            guard let cmd = e.slashCommand else { continue }
            d[cmd, default: [:]][e.model, default: 0] += e.grandTotal
        }
        return d.flatMap { (cmd, models) in
            models.map { StackedRow(category: "/\(cmd)", model: $0.key, value: $0.value) }
        }
    }

    func stackedByToolAndModel() -> [StackedRow] {
        var d: [String: [String: Int]] = [:]
        for e in self where e.model != "<synthetic>" {
            for tool in e.tools {
                d[tool, default: [:]][e.model, default: 0] += 1
            }
        }
        return d.flatMap { (tool, models) in
            models.map { StackedRow(category: tool, model: $0.key, value: $0.value) }
        }
    }
}

struct StackedRow: Identifiable, Hashable {
    let category: String
    let model: String
    let value: Int
    var id: String { "\(category)|\(model)" }
}

func formatCount(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
    return "\(n)"
}

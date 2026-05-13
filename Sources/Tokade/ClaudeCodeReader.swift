import Foundation
import os

actor ClaudeCodeReader {
    let projectsURL: URL
    private let log = Logger(subsystem: "com.bjamba.tokade", category: "ClaudeCodeReader")

    init(projectsURL: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")) {
        self.projectsURL = projectsURL
    }

    func readAllEvents() -> [UsageEvent] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsURL.path),
              let enumerator = fm.enumerator(at: projectsURL, includingPropertiesForKeys: nil) else {
            return []
        }
        var seen = Set<String>()
        var out: [UsageEvent] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            for event in parseFile(url) {
                let key = "\(event.sessionId ?? "")|\(event.messageId ?? UUID().uuidString)"
                if event.messageId != nil, !seen.insert(key).inserted { continue }
                out.append(event)
            }
        }
        return out
    }

    private func parseFile(_ url: URL) -> [UsageEvent] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.warning("read failed \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
        guard let text = String(data: data, encoding: .utf8) else {
            log.warning("non-utf8 JSONL: \(url.lastPathComponent, privacy: .public)")
            return []
        }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        var sessionCwd: [String: String] = [:]
        var sessionSlash: [String: String] = [:]  // first slash command per session
        var out: [UsageEvent] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            if let sid = obj["sessionId"] as? String, let cwd = obj["cwd"] as? String {
                sessionCwd[sid] = cwd
            }

            // Detect slash command per turn from last-prompt records.
            // The harness expands slash commands before they land in `user`
            // messages, but `last-prompt` preserves the literal typed input.
            if (obj["type"] as? String) == "last-prompt",
               let sid = obj["sessionId"] as? String {
                let lp = obj["lastPrompt"] as? String ?? ""
                if let cmd = parseSlashCommand(lp) {
                    sessionSlash[sid] = cmd
                } else {
                    sessionSlash.removeValue(forKey: sid)
                }
            }

            guard (obj["type"] as? String) == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any] else { continue }

            let tsStr = obj["timestamp"] as? String ?? ""
            let ts = isoFrac.date(from: tsStr) ?? isoPlain.date(from: tsStr) ?? Date.distantPast

            var tools: [String] = []
            if let content = msg["content"] as? [[String: Any]] {
                for block in content where (block["type"] as? String) == "tool_use" {
                    if let name = block["name"] as? String { tools.append(name) }
                }
            }

            let sid = obj["sessionId"] as? String
            let cwd = sid.flatMap { sessionCwd[$0] }

            out.append(UsageEvent(
                timestamp: ts,
                model: (msg["model"] as? String) ?? "unknown",
                inputTokens: usage["input_tokens"] as? Int ?? 0,
                cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
                cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
                outputTokens: usage["output_tokens"] as? Int ?? 0,
                sessionId: sid,
                messageId: msg["id"] as? String,
                cwd: cwd,
                tools: tools,
                slashCommand: sid.flatMap { sessionSlash[$0] }
            ))
        }
        return out
    }

    private func parseSlashCommand(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let rest = trimmed.dropFirst()
        // Take up to the first whitespace or punctuation.
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_:"))
        var name = ""
        for ch in rest.unicodeScalars {
            if allowed.contains(ch) { name.unicodeScalars.append(ch) } else { break }
        }
        return name.isEmpty ? nil : name
    }
}

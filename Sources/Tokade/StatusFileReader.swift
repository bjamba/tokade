import Foundation
import os

struct RateLimitWindow: Hashable {
    let usedPercentage: Double
    let resetsAt: Date
}

struct RateLimitSnapshot: Hashable {
    let fiveHour: RateLimitWindow?
    let sevenDay: RateLimitWindow?
    let modelDisplayName: String?
    let modelId: String?
    let sessionId: String?
    let capturedAt: Date
}

actor StatusFileReader {
    let url: URL
    private let log = Logger(subsystem: "com.bjamba.tokade", category: "StatusFileReader")

    init(url: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".tokade/last-status.json")) {
        self.url = url
    }

    func read() -> RateLimitSnapshot? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.warning("read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log.warning("JSON parse failed for last-status.json")
            return nil
        }

        let attrs = (try? fm.attributesOfItem(atPath: url.path)) ?? [:]
        let captured = (attrs[.modificationDate] as? Date) ?? Date()

        let model = obj["model"] as? [String: Any]
        let modelDisplay = model?["display_name"] as? String
        let modelId = model?["id"] as? String

        let limits = obj["rate_limits"] as? [String: Any]
        let five = parseWindow(limits?["five_hour"] as? [String: Any])
        let week = parseWindow(limits?["seven_day"] as? [String: Any])

        let sessionId = obj["session_id"] as? String
        if five == nil && week == nil && sessionId == nil { return nil }
        return RateLimitSnapshot(
            fiveHour: five,
            sevenDay: week,
            modelDisplayName: modelDisplay,
            modelId: modelId,
            sessionId: sessionId,
            capturedAt: captured
        )
    }

    private func parseWindow(_ obj: [String: Any]?) -> RateLimitWindow? {
        guard let obj else { return nil }
        let used = (obj["used_percentage"] as? Double)
            ?? (obj["used_percentage"] as? Int).map(Double.init)
            ?? Double.nan
        let resetsRaw = (obj["resets_at"] as? Double)
            ?? (obj["resets_at"] as? Int).map(Double.init)
            ?? 0
        guard used.isFinite else { return nil }
        return RateLimitWindow(
            usedPercentage: used,
            resetsAt: Date(timeIntervalSince1970: resetsRaw)
        )
    }
}

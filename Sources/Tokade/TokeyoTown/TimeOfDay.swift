import Foundation

/// Day-night cycle driver. v3.16 — tied to the user's real wall clock
/// so the town reflects their actual time of day. A `lightLevel ∈ [0, 1]`
/// (0 = midnight, 1 = noon) is the universal "how bright is it" signal
/// the renderer consumes for sky tinting, ground darkening, lantern
/// glow, and star visibility.
struct TimeOfDay: Equatable {
    var lightLevel: Double

    /// Real-wall-clock time. Sine wave peaking at 12:00, trough at 00:00.
    /// Dawn (~6 AM) and dusk (~6 PM) sit at 0.5.
    static func current(now: Date = .now) -> TimeOfDay {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .second], from: now)
        let hours = Double(comps.hour ?? 0)
            + Double(comps.minute ?? 0) / 60.0
            + Double(comps.second ?? 0) / 3600.0
        // hours = 6 → 0, hours = 12 → 1, hours = 18 → 0, hours = 0 → -1 → clamp
        let phase = (hours - 6.0) / 24.0 * 2 * .pi
        let raw = 0.5 + 0.5 * sin(phase)
        return TimeOfDay(lightLevel: raw)
    }

    /// Forced overrides used by the header day/night toggle.
    static let forcedDay = TimeOfDay(lightLevel: 1.0)
    static let forcedNight = TimeOfDay(lightLevel: 0.0)

    /// Human-readable mode label for the toggle.
    enum Mode: String, CaseIterable, Identifiable, Equatable {
        case auto, day, night
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: "Auto (clock)"
            case .day: "Forced day"
            case .night: "Forced night"
            }
        }

        var glyph: String {
            switch self {
            case .auto: "🕒"
            case .day: "☀️"
            case .night: "🌙"
            }
        }

        var next: Mode {
            switch self {
            case .auto: .day
            case .day: .night
            case .night: .auto
            }
        }
    }

    static func from(mode: Mode, now: Date = .now) -> TimeOfDay {
        switch mode {
        case .auto: return current(now: now)
        case .day: return forcedDay
        case .night: return forcedNight
        }
    }

    /// #45 — "bustle": how busy the user's current weekday/hour bucket is
    /// relative to their busiest bucket, normalized to `[0, 1]`.
    ///
    /// This layers liveliness ON TOP of the wall-clock day/night light: the
    /// town feels liveliest in the weekday-hour slots where the user actually
    /// codes (peak bucket → ~1.0) and quiet in their dead hours (→ ~0.0). It
    /// does NOT replace `lightLevel`; the renderer consumes both.
    ///
    /// Uses the same weekday×hour token bucketing as `HeatmapCard`: sum
    /// `grandTotal` per (weekday, hour), dropping `<synthetic>` events.
    /// Returns `0` (a safe, quiet default) when there's no real usage to
    /// learn a pattern from, so a brand-new install reads as a calm town
    /// rather than a falsely-bustling one.
    ///
    /// Pure (no clock or I/O beyond the injected `now`) so it's unit-testable.
    nonisolated static func bustleFactor(events: [UsageEvent], now: Date = .now) -> Double {
        let cal = Calendar.current
        var bucket: [Bucket: Int] = [:]
        for e in events where e.model != "<synthetic>" {
            let c = cal.dateComponents([.weekday, .hour], from: e.timestamp)
            guard let w = c.weekday, let h = c.hour else { continue }
            bucket[Bucket(weekday: w, hour: h), default: 0] += e.grandTotal
        }
        guard let peak = bucket.values.max(), peak > 0 else { return 0 }

        let nowComps = cal.dateComponents([.weekday, .hour], from: now)
        guard let w = nowComps.weekday, let h = nowComps.hour else { return 0 }
        let here = bucket[Bucket(weekday: w, hour: h)] ?? 0
        let factor = Double(here) / Double(peak)
        return min(1.0, max(0.0, factor))
    }

    private struct Bucket: Hashable {
        let weekday: Int
        let hour: Int
    }
}

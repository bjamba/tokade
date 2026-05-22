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
}

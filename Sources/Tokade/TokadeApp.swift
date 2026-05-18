import AppKit
import SwiftUI

@main
@MainActor
struct TokadeApp: App {
    @State private var store: UsageStore
    @State private var gaiden: TokenGaidenStore
    @State private var notifier: Notifier

    init() {
        let s = UsageStore()
        _store = State(initialValue: s)
        let n = Notifier()
        _notifier = State(initialValue: n)
        let g = TokenGaidenStore(notifier: n)
        _gaiden = State(initialValue: g)
        Task { @MainActor in
            // Faster than the original 30s default — Token Gaiden's tick reads
            // off the same events as the budget tab, so a tight 3s rhythm makes
            // the game feel reactive. mtime cache keeps re-polling cheap.
            s.startPolling(every: 3)
            await g.load()
        }
        // Background game-tick loop. Runs for the lifetime of the app so the
        // pet, encounters, auto-play, and notifications keep firing even when
        // the menu bar panel is closed. tick() is idempotent against the
        // event list (token accounting is keyed by message id), so re-ticking
        // while the panel is also open is harmless.
        // The usage alerter watches the same store for non-game milestones —
        // rate-limit threshold crossings and token bursts — and fires
        // notifications through the same Notifier when enabled.
        let alerter = UsageAlerter(notifier: n)
        Task { @MainActor [s, g, alerter] in
            // Small initial delay so the first refresh has data to chew on.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            while !Task.isCancelled {
                await g.tick(against: s.events,
                             usedPercentage: s.rateLimits?.fiveHour?.usedPercentage)
                alerter.evaluate(events: s.events, rateLimits: s.rateLimits)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store, gaiden: gaiden, notifier: notifier)
        } label: {
            Label {
                Text(menuBarText)
            } icon: {
                Image(nsImage: tokadeIcon(size: 18))
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarText: String {
        let base: String = if let five = store.rateLimits?.fiveHour {
            String(format: "%.0f%%", five.usedPercentage)
        } else {
            formatCount(store.fiveHourEvents.grandTotal())
        }
        return base + notifier.menuBarSuffix
    }
}

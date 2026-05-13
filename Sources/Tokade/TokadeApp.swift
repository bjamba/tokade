import SwiftUI
import AppKit

@main
struct TokadeApp: App {
    @State private var store: UsageStore

    init() {
        let s = UsageStore()
        _store = State(initialValue: s)
        Task { @MainActor in s.startPolling(every: 30) }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store)
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
        if let five = store.rateLimits?.fiveHour {
            return String(format: "%.0f%%", five.usedPercentage)
        }
        return formatCount(store.fiveHourEvents.grandTotal())
    }
}

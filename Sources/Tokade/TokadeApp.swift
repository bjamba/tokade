import AppKit
import SwiftUI

@main
@MainActor
struct TokadeApp: App {
    @State private var store: UsageStore
    @State private var gaiden: TokenGaidenStore

    init() {
        let s = UsageStore()
        _store = State(initialValue: s)
        let g = TokenGaidenStore()
        _gaiden = State(initialValue: g)
        Task { @MainActor in
            s.startPolling(every: 30)
            await g.load()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store, gaiden: gaiden)
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

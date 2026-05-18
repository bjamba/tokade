import AppKit
import Foundation
import Observation
import os.log
import UserNotifications

/// Combat resolution mode. Passive auto-resolves encounters; Active opens a
/// modal where the player picks Attack / Item / Run each turn.
enum CombatMode: String, CaseIterable, Identifiable {
    case passive, active
    var id: String { rawValue }
    var label: String {
        switch self {
        case .passive: return "Passive (auto)"
        case .active:  return "Active (turn-based)"
        }
    }
}

/// Forwards `willPresent` so macOS shows banners even when our menu bar app is
/// "active." Held by `Notifier` so it lives for the app lifetime.
final class TokadeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

/// Three modes for surfacing in-game events outside the panel:
/// - off:     no surfacing
/// - badge:   integer count in the menu-bar title ("Tokade • 3")
/// - banner:  macOS notification center banner (requires user permission)
enum NotificationMode: String, CaseIterable, Identifiable {
    case off
    case badge
    case banner
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off:    return "Off"
        case .badge:  return "Menu badge"
        case .banner: return "Notifications"
        }
    }
}

/// Owns the user's notification preference and the count of unseen events.
/// Reads/writes UserDefaults — settings persist across launches.
@MainActor
@Observable
final class Notifier {
    private(set) var mode: NotificationMode
    private(set) var unseenCount: Int = 0
    private(set) var crtMode: CRTMode
    private(set) var combatMode: CombatMode
    /// When on, the autopilot takes one decision per tick — heal, claim
    /// quests, attack in battle. Lets the game play itself when the player
    /// is away.
    private(set) var autoPlay: Bool = false
    /// When on, Tokade surfaces usage milestones (rate-limit thresholds at
    /// 50/75/90%, large 5-minute token bursts) through the same notification
    /// channel as game events. Separate toggle so users can opt in/out
    /// independently of game notifications.
    private(set) var usageAlerts: Bool = true
    /// Authorization status as last queried — the settings panel surfaces
    /// this so the player knows whether their banner mode will actually fire.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Tick events surface here for an in-panel feed (regardless of mode).
    private(set) var recent: [Entry] = []

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let body: String
        let timestamp: Date
        let kind: Kind
        enum Kind { case info, warning, danger }
    }

    private let log = Logger(subsystem: "com.bjamba.tokade", category: "Notifier")
    private let delegate = TokadeNotificationDelegate()
    private static let recentCap = 30

    static let defaultsKey = "tokade.notificationMode"
    static let crtKey = "tokade.crtMode"
    static let combatKey = "tokade.combatMode"
    static let autoPlayKey = "tokade.autoPlay"
    static let usageAlertsKey = "tokade.usageAlerts"

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? NotificationMode.badge.rawValue
        self.mode = NotificationMode(rawValue: raw) ?? .badge
        let crtRaw = UserDefaults.standard.string(forKey: Self.crtKey) ?? CRTMode.off.rawValue
        self.crtMode = CRTMode(rawValue: crtRaw) ?? .off
        let combatRaw = UserDefaults.standard.string(forKey: Self.combatKey) ?? CombatMode.passive.rawValue
        self.combatMode = CombatMode(rawValue: combatRaw) ?? .passive
        self.autoPlay = UserDefaults.standard.bool(forKey: Self.autoPlayKey)
        // Default ON: usage alerts are the kind of thing a user generally
        // wants the first time they install. They can disable in Settings.
        if UserDefaults.standard.object(forKey: Self.usageAlertsKey) == nil {
            self.usageAlerts = true
        } else {
            self.usageAlerts = UserDefaults.standard.bool(forKey: Self.usageAlertsKey)
        }
        UNUserNotificationCenter.current().delegate = delegate
        refreshAuthorizationStatus()
        // If user has already opted into banners across launches, re-request so
        // the system reflects current entitlement.
        if mode == .banner { requestAuthorization() }
    }

    /// Polls UNUserNotificationCenter to see whether the user has actually
    /// granted notification permission. Called on init + after each mode
    /// change so the settings panel can show a clear status.
    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    func setAutoPlay(_ on: Bool) {
        autoPlay = on
        UserDefaults.standard.set(on, forKey: Self.autoPlayKey)
    }

    func setUsageAlerts(_ on: Bool) {
        usageAlerts = on
        UserDefaults.standard.set(on, forKey: Self.usageAlertsKey)
    }

    func setMode(_ new: NotificationMode) {
        mode = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.defaultsKey)
        if new == .banner {
            requestAuthorization()
        }
        if new != .badge {
            unseenCount = 0
        }
        refreshAuthorizationStatus()
    }

    /// Send a test notification through the selected channel. Always pushes
    /// an Entry into `recent` (so the in-panel feed has something to show)
    /// and additionally fires badge / banner per mode.
    func sendTestNotification() {
        notify(title: "Test notification", body: "Sent from Tokade settings.")
    }

    func setCRTMode(_ new: CRTMode) {
        crtMode = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.crtKey)
    }

    func setCombatMode(_ new: CombatMode) {
        combatMode = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.combatKey)
    }

    /// Surface a Token Gaiden game event. The caller decides what's worth
    /// notifying — `Notifier` is dumb routing. The event is ALWAYS recorded
    /// into the in-panel feed so the player has feedback regardless of mode.
    func notify(title: String, body: String, kind: Entry.Kind = .info) {
        appendRecent(Entry(title: title, body: body, timestamp: Date(), kind: kind))
        switch mode {
        case .off:
            return
        case .badge:
            unseenCount += 1
        case .banner:
            postBanner(title: title, body: body)
        }
    }

    private func appendRecent(_ entry: Entry) {
        recent.append(entry)
        if recent.count > Self.recentCap {
            recent.removeFirst(recent.count - Self.recentCap)
        }
    }

    func clearRecent() {
        recent.removeAll()
    }

    /// Player opened the Tokade tab; treat all pending events as seen.
    func clearUnseen() {
        unseenCount = 0
    }

    /// What to append to the menu-bar title. Empty string if nothing to show.
    var menuBarSuffix: String {
        guard mode == .badge, unseenCount > 0 else { return "" }
        return " • \(unseenCount)"
    }

    // MARK: - Internals

    private func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self, log] granted, error in
            if let error {
                log.warning("notification authorization error: \(String(describing: error), privacy: .public)")
            } else if !granted {
                log.notice("notification authorization not granted by user")
            }
            Task { @MainActor in self?.refreshAuthorizationStatus() }
        }
    }

    private func postBanner(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [log] error in
            if let error {
                log.warning("notification post error: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

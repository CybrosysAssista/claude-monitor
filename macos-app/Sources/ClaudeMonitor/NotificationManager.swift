import Foundation
import UserNotifications

/// Fires a desktop notification when a window's remaining drops below the
/// threshold (default 20%), and re-arms once that window's resetsAt advances.
/// Mirrors the GNOME extension's notification rule (extension/lib/core/notifications.js).
final class NotificationManager {
    static let shared = NotificationManager()
    static let thresholdPct: Double = 20.0

    private struct Key: Hashable { let provider: String; let window: String }

    /// Tracks the resetsAt of the window the last time we fired for it.
    /// Re-arms when the snapshot's resetsAt advances (i.e., the window has
    /// rolled over).
    private var lastFiredAt: [Key: Date] = [:]
    private var hasRequestedAuth = false

    private init() {}

    func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuth else { return }
        hasRequestedAuth = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func check(provider: String, snapshot: UsageSnapshot) {
        evaluate(provider: provider, window: "session",
                 remaining: snapshot.sessionRemainingPct, resetsAt: snapshot.sessionResetsAt)
        evaluate(provider: provider, window: "weekly",
                 remaining: snapshot.weeklyRemainingPct, resetsAt: snapshot.weeklyResetsAt)
    }

    private func evaluate(provider: String, window: String,
                          remaining: Double?, resetsAt: Date?) {
        guard let r = remaining else { return }
        let key = Key(provider: provider, window: window)

        // Re-arm: if resetsAt changed (window rolled over), forget previous fire.
        if let last = lastFiredAt[key], let now = resetsAt, last != now {
            lastFiredAt.removeValue(forKey: key)
        }

        // Below threshold? Fire (once per reset cycle).
        guard r < Self.thresholdPct, lastFiredAt[key] == nil else { return }
        fire(provider: provider, window: window, remaining: r, resetsAt: resetsAt)
        lastFiredAt[key] = resetsAt
    }

    private func fire(provider: String, window: String, remaining: Double, resetsAt: Date?) {
        let content = UNMutableNotificationContent()
        content.title = "\(provider) \(window) low"
        let resetText = (resetsAt != nil) ? Formatting.fmtResets(resetsAt) : "no reset info"
        content.body = "\(Int(remaining.rounded()))% remaining · \(resetText)"
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)

        Log.info("app", "notification fired: \(provider) \(window) @ \(Int(remaining))%")
    }
}

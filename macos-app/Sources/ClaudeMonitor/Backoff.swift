import Foundation

enum Polling {
    /// Interval between automatic refresh cycles. Matches the GNOME extension's
    /// 180-second cadence and is consumed by both AppDelegate (the actual timer)
    /// and StatusBarController (the "next update in" footer).
    static let intervalSeconds: TimeInterval = 180
}

/// Per-provider exponential backoff. Mirrors the GNOME extension's behavior:
/// initial 30s, doubling per attempt, capped at 15 minutes. Triggers on rate
/// limits (immediate) or 2+ consecutive network errors. Resets on a clean OK.
struct BackoffState {
    static let initialDelay: TimeInterval = 30
    static let maxDelay:     TimeInterval = 15 * 60

    var attempt: Int = 0
    var consecutiveNetworkErrors: Int = 0
    var backoffUntil: Date?

    var isBackedOff: Bool {
        guard let until = backoffUntil else { return false }
        return Date() < until
    }

    mutating func recordSuccess() {
        attempt = 0
        consecutiveNetworkErrors = 0
        backoffUntil = nil
    }

    mutating func recordRateLimited() -> Date {
        attempt += 1
        consecutiveNetworkErrors = 0
        let delay = min(Self.initialDelay * pow(2.0, Double(attempt - 1)), Self.maxDelay)
        let until = Date().addingTimeInterval(delay)
        backoffUntil = until
        return until
    }

    mutating func recordNetworkError() -> Date? {
        consecutiveNetworkErrors += 1
        guard consecutiveNetworkErrors >= 2 else { return nil }
        attempt += 1
        let delay = min(Self.initialDelay * pow(2.0, Double(attempt - 1)), Self.maxDelay)
        let until = Date().addingTimeInterval(delay)
        backoffUntil = until
        return until
    }
}

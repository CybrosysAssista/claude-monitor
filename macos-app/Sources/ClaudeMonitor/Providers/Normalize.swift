import Foundation

/// Pure helpers that turn raw provider API payload values into the typed
/// fields used by `UsageSnapshot`. Mirrors the GNOME extension's
/// `lib/core/normalize.js`.
enum Normalize {

    /// Parse an ISO-8601 string from a Claude usage payload's `resets_at`.
    /// Tolerates fractional-second and no-fractional-second variants.
    static func parseIso(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }

    /// Given a utilization-percent value (0–100), return the remaining percent
    /// clamped to [0, 100]. Returns nil for non-numeric / non-finite inputs.
    static func remainingFromUtilization(_ utilization: Any?) -> Double? {
        let n: Double?
        if let d = utilization as? Double { n = d }
        else if let i = utilization as? Int { n = Double(i) }
        else if let s = utilization as? String { n = Double(s) }
        else { n = nil }
        guard let v = n, v.isFinite else { return nil }
        return max(0, min(100, 100 - v))
    }

    /// Convert a Codex payload's unix-seconds `reset_at` to a Date.
    static func unixToDate(_ v: Any?) -> Date? {
        let n: Double?
        if let d = v as? Double { n = d }
        else if let i = v as? Int { n = Double(i) }
        else { n = nil }
        guard let s = n, s.isFinite else { return nil }
        return Date(timeIntervalSince1970: s)
    }
}

import Foundation

struct UsageSnapshot {
    let sessionRemainingPct: Double?
    let weeklyRemainingPct: Double?
    let sessionResetsAt: Date?
    let weeklyResetsAt: Date?
}

enum ProviderResult {
    case success(UsageSnapshot)
    case notConfigured(installURL: String)
    case rateLimited(retryAfter: Date?)
    case authExpired
    case networkError(String)
    case keychainDenied(service: String)
    case failure(String)

    /// User-facing single-line message used in the popup when this is not a .success.
    /// For .success the caller renders rows instead.
    var friendlyMessage: String {
        switch self {
        case .success:               return ""
        case .notConfigured:         return ""  // caller renders custom CTA
        case .rateLimited(let when):
            if let w = when, w > Date() {
                let mins = max(1, Int(w.timeIntervalSinceNow / 60))
                return "Rate-limited — retrying in \(mins)m"
            }
            return "Rate-limited"
        case .authExpired:           return "Authentication expired — sign in again"
        case .networkError(let m):   return "Network error: \(m)"
        case .keychainDenied(let s): return "Keychain access denied for '\(s)'"
        case .failure(let m):        return m
        }
    }
}

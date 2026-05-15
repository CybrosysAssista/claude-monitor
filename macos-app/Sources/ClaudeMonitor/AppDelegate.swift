import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var timer: Timer?
    private var isRefreshing = false

    // Per-provider backoff state.
    private var claudeBackoff = BackoffState()
    private var codexBackoff  = BackoffState()

    // Latest results — used to keep the UI populated even when we skip a
    // provider due to backoff this tick.
    private var lastClaudeResult: ProviderResult?
    private var lastCodexResult: ProviderResult?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        statusBar.onRefresh = { [weak self] in self?.triggerRefresh() }
        statusBar.onQuit = { NSApp.terminate(nil) }

        NotificationManager.shared.requestAuthorizationIfNeeded()
        triggerRefresh()

        timer = Timer.scheduledTimer(withTimeInterval: Polling.intervalSeconds, repeats: true) { [weak self] _ in
            self?.triggerRefresh()
        }
    }

    private func triggerRefresh() {
        if isRefreshing { return }
        isRefreshing = true
        Log.info("app", "refresh begin")

        Task {
            async let cl = fetchClaude()
            async let co = fetchCodex()
            let results = await (cl, co)

            Log.info("app", "refresh done claude=\(Self.describe(results.0)) codex=\(Self.describe(results.1))")

            // Apply backoff state transitions
            applyBackoff(provider: "claude", result: results.0, state: &claudeBackoff)
            applyBackoff(provider: "codex",  result: results.1, state: &codexBackoff)

            // Notifications: only on successful snapshots
            if case .success(let s) = results.0 {
                NotificationManager.shared.check(provider: "Claude", snapshot: s)
            }
            if case .success(let s) = results.1 {
                NotificationManager.shared.check(provider: "Codex", snapshot: s)
            }

            let now = Date()
            await MainActor.run {
                self.lastClaudeResult = results.0
                self.lastCodexResult  = results.1
                self.statusBar.update(claude: results.0, codex: results.1, at: now)
                self.isRefreshing = false
            }
        }
    }

    private func fetchClaude() async -> ProviderResult {
        if claudeBackoff.isBackedOff {
            Log.info("claude", "skipped: backed off until \(claudeBackoff.backoffUntil?.description ?? "unknown")")
            return lastClaudeResult ?? .rateLimited(retryAfter: claudeBackoff.backoffUntil)
        }
        return await ClaudeProvider().fetch()
    }

    private func fetchCodex() async -> ProviderResult {
        if codexBackoff.isBackedOff {
            Log.info("codex", "skipped: backed off until \(codexBackoff.backoffUntil?.description ?? "unknown")")
            return lastCodexResult ?? .rateLimited(retryAfter: codexBackoff.backoffUntil)
        }
        return await CodexProvider().fetch()
    }

    private func applyBackoff(provider: String, result: ProviderResult, state: inout BackoffState) {
        switch result {
        case .success:
            if state.attempt > 0 || state.consecutiveNetworkErrors > 0 {
                Log.info(provider, "backoff reset")
            }
            state.recordSuccess()
        case .rateLimited:
            let until = state.recordRateLimited()
            Log.info(provider, "rate-limited; backing off until \(until)")
        case .networkError:
            if let until = state.recordNetworkError() {
                Log.info(provider, "2+ network errors; backing off until \(until)")
            }
        default:
            break
        }
    }

    private static func describe(_ r: ProviderResult) -> String {
        switch r {
        case .success(let s):
            return "OK(session=\(s.sessionRemainingPct?.description ?? "nil"),weekly=\(s.weeklyRemainingPct?.description ?? "nil"))"
        case .notConfigured:    return "NOT_CONFIGURED"
        case .rateLimited:      return "RATE_LIMITED"
        case .authExpired:      return "AUTH_EXPIRED"
        case .networkError(let m):   return "NETWORK_ERROR(\(m))"
        case .keychainDenied(let s): return "KEYCHAIN_DENIED(\(s))"
        case .failure(let m):   return "FAIL(\(m))"
        }
    }
}

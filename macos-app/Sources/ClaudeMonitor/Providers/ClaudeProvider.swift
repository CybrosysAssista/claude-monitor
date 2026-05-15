import Foundation

struct ClaudeProvider {
    static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let usageURL   = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let clientID   = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let betaHeader = "oauth-2025-04-20"

    static let installURL = "https://docs.anthropic.com/claude-code"

    func fetch() async -> ProviderResult {
        let creds: [String: Any]
        let kc = Keychain.readGenericPassword(service: "Claude Code-credentials")
        let fileCreds: [String: Any]?
        do { fileCreds = try Credentials.read(path: Credentials.claudePath) }
        catch { fileCreds = nil; Log.info("claude", "file creds unavailable: \(error.localizedDescription)") }

        switch kc {
        case .found(let data):
            Log.info("claude", "keychain read OK, bytes=\(data.count)")
            guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return .failure("Keychain JSON parse failed")
            }
            Log.info("claude", "keychain parsed, top-level keys=\(Array(parsed.keys))")
            creds = parsed
        case .denied:
            Log.info("claude", "keychain access denied by user")
            return .keychainDenied(service: "Claude Code-credentials")
        case .error(let s):
            Log.info("claude", "keychain error status=\(s)")
            if let fc = fileCreds { creds = fc } else {
                return .failure("Keychain error \(s)")
            }
        case .notFound:
            Log.info("claude", "keychain item not found")
            if let fc = fileCreds {
                Log.info("claude", "file read OK, top-level keys=\(Array(fc.keys))")
                creds = fc
            } else {
                return .notConfigured(installURL: Self.installURL)
            }
        }

        // Claude Code stores either { claudeAiOauth: {...} } or the oauth dict at top level.
        let oauth: [String: Any]
        if let wrapped = creds["claudeAiOauth"] as? [String: Any] {
            oauth = wrapped
        } else if creds["accessToken"] != nil || creds["access_token"] != nil
                || creds["refreshToken"] != nil || creds["refresh_token"] != nil {
            oauth = creds
        } else {
            return .failure("missing oauth fields in Claude credentials")
        }

        let refresh = (oauth["refreshToken"] as? String) ?? (oauth["refresh_token"] as? String)
        let expiry  = oauth["expiresAt"] ?? oauth["expires_at"]
        var token   = (oauth["accessToken"] as? String) ?? (oauth["access_token"] as? String)

        do {
            Log.info("claude", "have token=\(token != nil) expired=\(Credentials.isExpired(expiry))")
            if token == nil || Credentials.isExpired(expiry) {
                guard let r = refresh else { return .failure("missing refresh token") }
                Log.info("claude", "refreshing token")
                token = try await Self.refreshToken(r)
                Log.info("claude", "refresh OK")
            }
            guard var t = token else { return .failure("no access token") }

            var res = try await Self.fetchUsage(token: t)
            Log.info("claude", "usage status=\(res.status) bytes=\(res.data.count)")
            if res.status == 401, let r = refresh {
                Log.info("claude", "401, refreshing and retrying")
                t = try await Self.refreshToken(r)
                res = try await Self.fetchUsage(token: t)
                Log.info("claude", "retry status=\(res.status) bytes=\(res.data.count)")
            }
            guard res.ok else {
                let bodyPreview = String(data: res.data.prefix(300), encoding: .utf8) ?? "<binary>"
                Log.info("claude", "usage NOT OK \(res.status), body=\(bodyPreview)")
                switch res.status {
                case 401: return .authExpired
                case 429: return .rateLimited(retryAfter: nil)
                default:  return .failure("Claude API \(res.status)")
                }
            }

            let payload = try res.jsonObject()
            Log.info("claude", "usage payload keys=\(Array(payload.keys))")
            let snap = Self.normalize(payload)
            Log.info("claude", "normalized session=\(snap.sessionRemainingPct?.description ?? "nil") weekly=\(snap.weeklyRemainingPct?.description ?? "nil")")
            return .success(snap)
        } catch let err as URLError {
            Log.info("claude", "URLError: \(err.localizedDescription)")
            return .networkError(err.localizedDescription)
        } catch {
            Log.info("claude", "error: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    static func refreshToken(_ refresh: String) async throws -> String {
        let data = try await HTTPClient.postForm(refreshURL, fields: [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ])
        if let t = data["access_token"] as? String { return t }
        if let t = data["accessToken"] as? String { return t }
        throw NSError(domain: "ClaudeProvider", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "No access token in Claude refresh response"])
    }

    static func fetchUsage(token: String) async throws -> HTTPResponse {
        try await HTTPClient.get(usageURL, headers: [
            "authorization": "Bearer \(token)",
            "anthropic-beta": betaHeader,
        ])
    }

    static func normalize(_ payload: [String: Any]) -> UsageSnapshot {
        let fh = payload["five_hour"] as? [String: Any]
        let sd = payload["seven_day"] as? [String: Any]
        return UsageSnapshot(
            sessionRemainingPct: Normalize.remainingFromUtilization(fh?["utilization"]),
            weeklyRemainingPct:  Normalize.remainingFromUtilization(sd?["utilization"]),
            sessionResetsAt:     Normalize.parseIso(fh?["resets_at"] as? String),
            weeklyResetsAt:      Normalize.parseIso(sd?["resets_at"] as? String)
        )
    }
}

import Foundation

struct CodexProvider {
    static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    static let usageURL   = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let clientID   = "app_EMoamEEZ73f0CkXaXp7hrann"

    static let installURL = "https://github.com/openai/codex"

    func fetch() async -> ProviderResult {
        let creds: [String: Any]
        let kc = Keychain.readGenericPassword(service: "Codex Auth")
        let fileCreds: [String: Any]?
        do { fileCreds = try Credentials.read(path: Credentials.codexPath) }
        catch { fileCreds = nil; Log.info("codex", "file creds unavailable: \(error.localizedDescription)") }

        switch kc {
        case .found(let data):
            Log.info("codex", "keychain read OK, bytes=\(data.count)")
            guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return .failure("Keychain JSON parse failed")
            }
            Log.info("codex", "keychain parsed, top-level keys=\(Array(parsed.keys))")
            creds = parsed
        case .denied:
            Log.info("codex", "keychain access denied by user")
            return .keychainDenied(service: "Codex Auth")
        case .error(let s):
            Log.info("codex", "keychain error status=\(s)")
            if let fc = fileCreds { creds = fc } else {
                return .failure("Keychain error \(s)")
            }
        case .notFound:
            Log.info("codex", "keychain item not found")
            if let fc = fileCreds {
                Log.info("codex", "file read OK, top-level keys=\(Array(fc.keys))")
                creds = fc
            } else {
                return .notConfigured(installURL: Self.installURL)
            }
        }

        guard let tokens = creds["tokens"] as? [String: Any] else {
            Log.info("codex", "missing 'tokens' key")
            return .failure("missing tokens in credentials")
        }
        let refresh   = tokens["refresh_token"] as? String
        let accountId = tokens["account_id"] as? String
        var token     = tokens["access_token"] as? String

        if token == nil && refresh == nil {
            return .failure("missing tokens in credentials")
        }

        do {
            Log.info("codex", "have token=\(token != nil) have refresh=\(refresh != nil) have accountId=\(accountId != nil)")
            if token == nil {
                guard let r = refresh else { return .failure("no refresh token") }
                Log.info("codex", "refreshing token")
                token = try await Self.refreshToken(r)
                Log.info("codex", "refresh OK")
            }
            guard var t = token else { return .failure("no access token") }

            var res = try await Self.fetchUsage(token: t, accountId: accountId)
            Log.info("codex", "usage status=\(res.status) bytes=\(res.data.count)")
            if res.status == 401, let r = refresh {
                Log.info("codex", "401, refreshing and retrying")
                t = try await Self.refreshToken(r)
                res = try await Self.fetchUsage(token: t, accountId: accountId)
                Log.info("codex", "retry status=\(res.status) bytes=\(res.data.count)")
            }
            guard res.ok else {
                let bodyPreview = String(data: res.data.prefix(300), encoding: .utf8) ?? "<binary>"
                Log.info("codex", "usage NOT OK \(res.status), body=\(bodyPreview)")
                switch res.status {
                case 401: return .authExpired
                case 429: return .rateLimited(retryAfter: nil)
                default:  return .failure("Codex API \(res.status)")
                }
            }

            let payload = try res.jsonObject()
            Log.info("codex", "usage payload keys=\(Array(payload.keys))")
            let snap = Self.normalize(payload)
            Log.info("codex", "normalized session=\(snap.sessionRemainingPct?.description ?? "nil") weekly=\(snap.weeklyRemainingPct?.description ?? "nil")")
            return .success(snap)
        } catch let err as URLError {
            Log.info("codex", "URLError: \(err.localizedDescription)")
            return .networkError(err.localizedDescription)
        } catch {
            Log.info("codex", "error: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    static func refreshToken(_ refresh: String) async throws -> String {
        let data = try await HTTPClient.postForm(refreshURL, fields: [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refresh,
        ])
        guard let t = data["access_token"] as? String else {
            throw NSError(domain: "CodexProvider", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No access token in Codex refresh response"])
        }
        return t
    }

    static func fetchUsage(token: String, accountId: String?) async throws -> HTTPResponse {
        var headers = ["authorization": "Bearer \(token)"]
        if let id = accountId { headers["ChatGPT-Account-Id"] = id }
        return try await HTTPClient.get(usageURL, headers: headers)
    }

    static func normalize(_ payload: [String: Any]) -> UsageSnapshot {
        let rl = payload["rate_limit"] as? [String: Any]
        let p  = rl?["primary_window"]   as? [String: Any]
        let s  = rl?["secondary_window"] as? [String: Any]
        return UsageSnapshot(
            sessionRemainingPct: Normalize.remainingFromUtilization(p?["used_percent"]),
            weeklyRemainingPct:  Normalize.remainingFromUtilization(s?["used_percent"]),
            sessionResetsAt:     Normalize.unixToDate(p?["reset_at"]),
            weeklyResetsAt:      Normalize.unixToDate(s?["reset_at"])
        )
    }
}

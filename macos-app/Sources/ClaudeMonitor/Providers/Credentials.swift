import Foundation

enum Credentials {
    static let claudePath = (NSString("~/.claude/.credentials.json").expandingTildeInPath)
    static let codexPath  = (NSString("~/.codex/auth.json").expandingTildeInPath)

    static func read(path: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Credentials", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }
        return json
    }

    /// Has the cached access-token expired? Accepts numeric (epoch seconds or
    /// milliseconds) or ISO-8601 string forms — Claude/Codex CLIs have used
    /// both conventions in their credential blobs.
    static func isExpired(_ expiry: Any?) -> Bool {
        guard let expiry = expiry else { return false }
        let nowMs = Date().timeIntervalSince1970 * 1000

        if let d = expiry as? Double {
            let ms = d > 1e12 ? d : d * 1000
            return nowMs >= ms
        }
        if let i = expiry as? Int {
            let d = Double(i)
            let ms = d > 1e12 ? d : d * 1000
            return nowMs >= ms
        }
        if let s = expiry as? String, let date = Normalize.parseIso(s) {
            return nowMs >= date.timeIntervalSince1970 * 1000
        }
        return false
    }
}

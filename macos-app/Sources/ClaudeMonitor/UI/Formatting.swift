import Foundation

enum Formatting {

    /// Long form for popup rows: "76% used" or "24% left" (or "--").
    static func pctLong(_ remaining: Double?, inverted: Bool) -> String {
        guard let v = remaining else { return "--" }
        let used = Int((100 - v).rounded())
        let left = Int(v.rounded())
        return inverted ? "\(left)% left" : "\(used)% used"
    }

    /// Compact form for tray label chunks: "76%" or "24%" — sign of `inverted`
    /// determines which value is shown. Always exactly one number, no suffix.
    static func pctTray(_ remaining: Double?, inverted: Bool) -> String {
        guard let v = remaining else { return "?" }
        let used = Int((100 - v).rounded())
        let left = Int(v.rounded())
        return inverted ? "\(left)%" : "\(used)%"
    }

    /// "resets in 3h 30m", or "--" if no/past date.
    static func fmtResets(_ date: Date?) -> String {
        guard let d = date else { return "--" }
        let diff = d.timeIntervalSinceNow
        if diff <= 0 { return "--" }
        let totalMin = Int(diff / 60)
        let days  = totalMin / 1440
        let hours = (totalMin % 1440) / 60
        let mins  = totalMin % 60
        var parts: [String] = []
        if days  > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if mins  > 0 || parts.isEmpty { parts.append("\(mins)m") }
        return "resets in \(parts.joined(separator: " "))"
    }

    static func minRemaining(_ a: Double?, _ b: Double?) -> Double? {
        switch (a, b) {
        case (nil, nil): return nil
        case (.some(let x), nil): return x
        case (nil, .some(let y)): return y
        case (.some(let x), .some(let y)): return min(x, y)
        }
    }
}

import Foundation

enum PanelMode: String, CaseIterable, Codable {
    case none           = "none"
    case overall        = "overall"
    case all            = "all"
    case claude         = "claude"
    case claudeSession  = "claude-session"
    case claudeWeekly   = "claude-weekly"
    case codex          = "codex"
    case codexSession   = "codex-session"
    case codexWeekly    = "codex-weekly"

    var displayName: String {
        switch self {
        case .none:          return "None"
        case .overall:       return "Overall (lowest %)"
        case .all:           return "All metrics"
        case .claude:        return "Claude"
        case .claudeSession: return "Claude · Session"
        case .claudeWeekly:  return "Claude · Weekly"
        case .codex:         return "Codex"
        case .codexSession:  return "Codex · Session"
        case .codexWeekly:   return "Codex · Weekly"
        }
    }
}

extension Notification.Name {
    static let settingsDidChange = Notification.Name("com.cybrosys.claudemonitor.settingsDidChange")
}

final class Settings {
    static let shared = Settings()

    private enum Key {
        static let displayInverted   = "displayInverted"
        static let panelLabelModes   = "panelLabelModes"
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.displayInverted: false,
            Key.panelLabelModes: [PanelMode.overall.rawValue],
        ])
    }

    var displayInverted: Bool {
        get { defaults.bool(forKey: Key.displayInverted) }
        set {
            defaults.set(newValue, forKey: Key.displayInverted)
            broadcast()
        }
    }

    var panelLabelModes: Set<PanelMode> {
        get {
            let raw = defaults.stringArray(forKey: Key.panelLabelModes) ?? [PanelMode.overall.rawValue]
            return Set(raw.compactMap { PanelMode(rawValue: $0) })
        }
        set {
            let normalized = normalizeModes(newValue)
            defaults.set(normalized.map { $0.rawValue }, forKey: Key.panelLabelModes)
            broadcast()
        }
    }

    /// Resolves group-toggle semantics: `.claude` group is *not* a render mode;
    /// it expands into `.claudeSession + .claudeWeekly` for rendering purposes.
    /// We persist whichever set the user picks, but rendering uses this expansion.
    static func expandForRendering(_ modes: Set<PanelMode>) -> [PanelMode] {
        if modes.contains(.none) { return [.none] }
        if modes.contains(.overall) && modes.count == 1 { return [.overall] }
        if modes.contains(.all) { return [.claudeSession, .claudeWeekly, .codexSession, .codexWeekly] }

        var expanded = Set<PanelMode>()
        for m in modes {
            switch m {
            case .claude: expanded.insert(.claudeSession); expanded.insert(.claudeWeekly)
            case .codex:  expanded.insert(.codexSession);  expanded.insert(.codexWeekly)
            case .none, .overall, .all: continue
            default: expanded.insert(m)
            }
        }
        // Stable ordering: Claude before Codex, session before weekly.
        let order: [PanelMode] = [.claudeSession, .claudeWeekly, .codexSession, .codexWeekly]
        return order.filter { expanded.contains($0) }
    }

    /// Collapse explicit mode set back to whatever group representation makes the
    /// Configure submenu state visually consistent.
    private func normalizeModes(_ modes: Set<PanelMode>) -> Set<PanelMode> {
        if modes.isEmpty { return [.overall] }
        if modes.contains(.none) { return [.none] }
        return modes
    }

    private func broadcast() {
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
}

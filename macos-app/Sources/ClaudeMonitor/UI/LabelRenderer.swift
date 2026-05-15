import AppKit

enum LabelRenderer {

    /// Build the menu bar status item's attributed title based on selected modes,
    /// the inverted-display preference, and the latest provider snapshots.
    static func tray(
        modes: Set<PanelMode>,
        inverted: Bool,
        claude: UsageSnapshot?,
        codex: UsageSnapshot?,
        claudeIcon: NSImage?,
        codexIcon: NSImage?
    ) -> NSAttributedString {
        let effective = Settings.expandForRendering(modes)

        // .none → render an adaptive dash so the button is still hittable.
        if effective == [.none] {
            return NSAttributedString(string: "—", attributes: [
                .font: NSFont.menuBarFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }

        // .overall → both icons + single worst percentage.
        if effective == [.overall] {
            let worst = minAcross(claude: claude, codex: codex)
            let out = NSMutableAttributedString()
            appendIcon(out, image: claudeIcon)
            appendIcon(out, image: codexIcon)
            out.append(space())
            out.append(pctAttr(worst, inverted: inverted))
            return out
        }

        // Otherwise: group by provider, render each group as "[icon] S: X%  W: Y%",
        // joined by " · " across groups.
        let claudeKeys: [PanelMode] = effective.filter { (m: PanelMode) in
            m == .claudeSession || m == .claudeWeekly
        }
        let codexKeys: [PanelMode] = effective.filter { (m: PanelMode) in
            m == .codexSession || m == .codexWeekly
        }

        let out = NSMutableAttributedString()

        if !claudeKeys.isEmpty {
            appendIcon(out, image: claudeIcon)
            out.append(space())
            appendGroup(out, keys: claudeKeys, claude: claude, codex: codex, inverted: inverted)
        }
        if !codexKeys.isEmpty {
            if !claudeKeys.isEmpty { out.append(separator()) }
            appendIcon(out, image: codexIcon)
            out.append(space())
            appendGroup(out, keys: codexKeys, claude: claude, codex: codex, inverted: inverted)
        }

        return out
    }

    // MARK: - Helpers

    private static func appendGroup(
        _ out: NSMutableAttributedString,
        keys: [PanelMode],
        claude: UsageSnapshot?,
        codex: UsageSnapshot?,
        inverted: Bool
    ) {
        var first = true
        for k in keys {
            if !first { out.append(NSAttributedString(string: "  ", attributes: baseAttrs())) }
            first = false
            let (label, pct) = labelAndPct(for: k, claude: claude, codex: codex)
            out.append(NSAttributedString(string: label, attributes: baseAttrs()))
            out.append(pctAttr(pct, inverted: inverted))
        }
    }

    private static func labelAndPct(
        for mode: PanelMode,
        claude: UsageSnapshot?,
        codex: UsageSnapshot?
    ) -> (String, Double?) {
        switch mode {
        case .claudeSession: return ("S:", claude?.sessionRemainingPct)
        case .claudeWeekly:  return ("W:", claude?.weeklyRemainingPct)
        case .codexSession:  return ("S:", codex?.sessionRemainingPct)
        case .codexWeekly:   return ("W:", codex?.weeklyRemainingPct)
        default: return ("", nil)
        }
    }

    private static func minAcross(claude: UsageSnapshot?, codex: UsageSnapshot?) -> Double? {
        let vals = [
            claude?.sessionRemainingPct, claude?.weeklyRemainingPct,
            codex?.sessionRemainingPct,  codex?.weeklyRemainingPct,
        ].compactMap { $0 }
        return vals.isEmpty ? nil : vals.min()
    }

    private static func pctAttr(_ remaining: Double?, inverted: Bool) -> NSAttributedString {
        let str = Formatting.pctTray(remaining, inverted: inverted)
        return NSAttributedString(string: str, attributes: [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: ThresholdColors.color(forRemainingPct: remaining),
        ])
    }

    private static func appendIcon(_ out: NSMutableAttributedString, image: NSImage?) {
        guard let image = image else { return }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -3, width: 14, height: 14)
        out.append(NSAttributedString(attachment: attachment))
    }

    private static func space() -> NSAttributedString {
        NSAttributedString(string: " ", attributes: baseAttrs())
    }

    private static func separator() -> NSAttributedString {
        NSAttributedString(string: "  ·  ", attributes: [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    private static func baseAttrs() -> [NSAttributedString.Key: Any] {
        [.font: NSFont.menuBarFont(ofSize: 0)]
    }
}

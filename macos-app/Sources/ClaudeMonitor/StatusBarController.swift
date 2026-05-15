import AppKit
import ServiceManagement

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private var lastClaude: ProviderResult?
    private var lastCodex: ProviderResult?
    private var lastPolledAt: Date?

    private var liveTimer: Timer?  // refreshes countdowns + footer while menu is open
    private var menu: NSMenu!

    // Icons. Claude keeps brand colors; Codex is re-tinted per appearance.
    private var claudeIcon: NSImage?
    private var codexIcon: NSImage?
    private var appearanceObservation: NSKeyValueObservation?

    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.claudeIcon = Self.loadIcon(named: "claude")
        self.codexIcon  = Self.loadIcon(named: "codex")
        super.init()
        self.statusItem.button?.title = "…"
        rebuildMenu()

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: .settingsDidChange, object: nil)

        // Re-tint Codex icon when the user toggles Light/Dark mode.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            self?.codexIcon = Self.loadIcon(named: "codex")
            self?.rebuildLabel()
            self?.rebuildMenu()
        }
    }

    deinit {
        liveTimer?.invalidate()
        appearanceObservation?.invalidate()
    }

    // MARK: - Public update

    func update(claude: ProviderResult, codex: ProviderResult, at: Date) {
        self.lastClaude = claude
        self.lastCodex = codex
        self.lastPolledAt = at
        rebuildLabel()
        rebuildMenu()
    }

    @objc private func settingsChanged() {
        rebuildLabel()
        rebuildMenu()
    }

    // MARK: - Tray label

    private func rebuildLabel() {
        let modes = Settings.shared.panelLabelModes
        let inverted = Settings.shared.displayInverted
        let attr = LabelRenderer.tray(
            modes: modes,
            inverted: inverted,
            claude: snapshot(of: lastClaude),
            codex:  snapshot(of: lastCodex),
            claudeIcon: claudeIcon,
            codexIcon: codexIcon
        )
        statusItem.button?.attributedTitle = attr
    }

    private func snapshot(of res: ProviderResult?) -> UsageSnapshot? {
        if case .success(let s) = res { return s }
        return nil
    }

    // MARK: - Dropdown menu

    private func rebuildMenu() {
        let m = NSMenu()
        m.delegate = self

        addProviderSection(to: m, title: "Claude", iconName: "claude", result: lastClaude)
        m.addItem(.separator())
        addProviderSection(to: m, title: "Codex",  iconName: "codex",  result: lastCodex)
        m.addItem(.separator())

        // Footer: next update in Xs
        let footer = NSMenuItem(title: nextUpdateText(), action: nil, keyEquivalent: "")
        footer.isEnabled = false
        footer.tag = MenuTag.footer.rawValue
        m.addItem(footer)

        m.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshTriggered), keyEquivalent: "r")
        refresh.target = self
        m.addItem(refresh)

        m.addItem(buildConfigureSubmenu())

        let launch = NSMenuItem(title: "Launch at Login",
                                action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        m.addItem(launch)

        m.addItem(.separator())
        let about = NSMenuItem(title: "About Claude Monitor", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        m.addItem(about)

        let quit = NSMenuItem(title: "Quit Claude Monitor", action: #selector(quitTriggered), keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)

        self.menu = m
        statusItem.menu = m
    }

    private enum MenuTag: Int {
        case footer = 1001
    }

    private func addProviderSection(to menu: NSMenu, title: String, iconName: String, result: ProviderResult?) {
        let header = NSMenuItem()
        header.view = SectionHeaderView(title: title, icon: providerIcon(named: iconName))
        menu.addItem(header)

        switch result {
        case .some(.success(let snap)):
            menu.addItem(makeRowItem(label: "Session", remaining: snap.sessionRemainingPct, resetsAt: snap.sessionResetsAt))
            menu.addItem(makeRowItem(label: "Weekly",  remaining: snap.weeklyRemainingPct,  resetsAt: snap.weeklyResetsAt))
        case .some(.notConfigured(let url)):
            let cliName = (title == "Claude") ? "Claude Code CLI" : "Codex CLI"
            let info = NSMenuItem(title: "  No \(cliName) signed in", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)

            let install = NSMenuItem(title: "  → Install \(cliName)", action: #selector(openInstallURL(_:)), keyEquivalent: "")
            install.target = self
            install.representedObject = url
            menu.addItem(install)
        case .some(let other):
            let item = NSMenuItem(title: "  ⚠ \(other.friendlyMessage)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        case .none:
            let item = NSMenuItem(title: "  Loading…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    private func makeRowItem(label: String, remaining: Double?, resetsAt: Date?) -> NSMenuItem {
        let item = NSMenuItem()
        let view = ProviderRowView(label: label, remaining: remaining, resetsAt: resetsAt,
                                   inverted: Settings.shared.displayInverted)
        item.view = view
        return item
    }

    // MARK: - Configure submenu

    private func buildConfigureSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Configure", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Configure")
        let active = Settings.shared.panelLabelModes

        for mode in PanelMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(togglePanelMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = stateFor(mode: mode, active: active)
            sub.addItem(item)
        }

        sub.addItem(.separator())
        let reversed = NSMenuItem(title: "↕ Reversed (% left)",
                                  action: #selector(toggleReversed), keyEquivalent: "")
        reversed.target = self
        reversed.state = Settings.shared.displayInverted ? .on : .off
        sub.addItem(reversed)

        parent.submenu = sub
        return parent
    }

    private func stateFor(mode: PanelMode, active: Set<PanelMode>) -> NSControl.StateValue {
        // Group items reflect "all-on" / "mixed" / "off".
        switch mode {
        case .claude:
            let on  = active.contains(.claudeSession) && active.contains(.claudeWeekly)
            let any = active.contains(.claudeSession) || active.contains(.claudeWeekly) || active.contains(.claude)
            if on { return .on } ; if any { return .mixed } ; return .off
        case .codex:
            let on  = active.contains(.codexSession) && active.contains(.codexWeekly)
            let any = active.contains(.codexSession) || active.contains(.codexWeekly) || active.contains(.codex)
            if on { return .on } ; if any { return .mixed } ; return .off
        default:
            return active.contains(mode) ? .on : .off
        }
    }

    // MARK: - Footer / next-update

    private func nextUpdateText() -> String {
        guard let last = lastPolledAt else { return "Polling…" }
        let next = last.addingTimeInterval(Polling.intervalSeconds)
        let remaining = next.timeIntervalSinceNow
        if remaining <= 0 { return "Update due" }
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        if m > 0 { return String(format: "Next update in %dm %02ds", m, s) }
        return String(format: "Next update in %ds", s)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickLive()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        liveTimer?.invalidate()
        liveTimer = nil
    }

    private func tickLive() {
        guard let menu = menu else { return }

        if let footer = menu.items.first(where: { $0.tag == MenuTag.footer.rawValue }) {
            footer.title = nextUpdateText()
        }

        // Refresh each provider row's countdown text. No submenu contains row
        // views, so this is a single-level walk.
        for item in menu.items {
            if let view = item.view as? ProviderRowView { view.refreshCountdown() }
        }
    }

    // MARK: - Actions

    @objc private func togglePanelMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = PanelMode(rawValue: raw) else { return }
        var active = Settings.shared.panelLabelModes

        switch mode {
        case .none:
            active = [.none]
        case .overall:
            active = [.overall]
        case .all:
            active = [.all]
        case .claude:
            // Group toggle: turn both Claude items on/off based on current state.
            let bothOn = active.contains(.claudeSession) && active.contains(.claudeWeekly)
            active.remove(.none); active.remove(.overall); active.remove(.all); active.remove(.claude)
            if bothOn {
                active.remove(.claudeSession); active.remove(.claudeWeekly)
            } else {
                active.insert(.claudeSession); active.insert(.claudeWeekly)
            }
        case .codex:
            let bothOn = active.contains(.codexSession) && active.contains(.codexWeekly)
            active.remove(.none); active.remove(.overall); active.remove(.all); active.remove(.codex)
            if bothOn {
                active.remove(.codexSession); active.remove(.codexWeekly)
            } else {
                active.insert(.codexSession); active.insert(.codexWeekly)
            }
        default:
            active.remove(.none); active.remove(.overall); active.remove(.all)
            if active.contains(mode) { active.remove(mode) } else { active.insert(mode) }
        }

        if active.isEmpty { active = [.overall] }
        Settings.shared.panelLabelModes = active
    }

    @objc private func toggleReversed() {
        Settings.shared.displayInverted.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                Log.info("app", "launch-at-login disabled")
            } else {
                try SMAppService.mainApp.register()
                Log.info("app", "launch-at-login enabled")
            }
            rebuildMenu()
        } catch {
            Log.info("app", "launch-at-login toggle failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Couldn't update Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nTip: move Claude Monitor.app into /Applications first — that's required for the login-items service to register the app reliably."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func refreshTriggered() { onRefresh?() }

    @objc private func openInstallURL(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String, let url = URL(string: s) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)

        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
        ]
        func linkAttrs(_ url: String) -> [NSAttributedString.Key: Any] {
            body.merging([
                .link: URL(string: url)!,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]) { _, b in b }
        }

        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(
            string: "Track Claude and Codex AI usage limits in the macOS menu bar.\n\n",
            attributes: body))

        credits.append(NSAttributedString(string: "Built by ", attributes: body))
        credits.append(NSAttributedString(string: "Cybrosys Assista",
                                          attributes: linkAttrs("https://assista.cybrosys.com")))
        credits.append(NSAttributedString(string: "\n", attributes: body))

        credits.append(NSAttributedString(string: "Source on ", attributes: body))
        credits.append(NSAttributedString(string: "GitHub",
                                          attributes: linkAttrs("https://github.com/CybrosysAssista/claude-monitor")))
        credits.append(NSAttributedString(string: "\n\n", attributes: body))

        credits.append(NSAttributedString(string: "MIT License · © 2026 Cybrosys Assista",
                                          attributes: body))

        let alignment = NSMutableParagraphStyle()
        alignment.alignment = .center
        credits.addAttribute(.paragraphStyle, value: alignment,
                             range: NSRange(location: 0, length: credits.length))

        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.credits: credits,
        ])
    }

    @objc private func quitTriggered() { onQuit?() }

    // MARK: - Icons

    private func providerIcon(named name: String) -> NSImage? {
        switch name {
        case "claude": return claudeIcon
        case "codex":  return codexIcon
        default: return nil
        }
    }

    private static func loadIcon(named name: String) -> NSImage? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "svg"),
            Bundle.module.url(forResource: name, withExtension: "svg"),
        ]
        for url in candidates.compactMap({ $0 }) {
            if let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: 16, height: 16)
                if name == "codex" {
                    // codex.svg ships with fill="white" — invisible on light menu
                    // bars and on light-mode dropdown backgrounds. Re-tint with
                    // the active labelColor (resolved via NSAppearance below in
                    // tintedForCurrentAppearance()).
                    return tintedForCurrentAppearance(base: img)
                }
                return img
            }
        }
        return nil
    }

    /// Produces an NSImage that's the alpha mask of `base` filled with the
    /// current appearance's labelColor — i.e., dark in light mode, light in
    /// dark mode. Re-render this whenever appearance changes.
    private static func tintedForCurrentAppearance(base: NSImage) -> NSImage {
        let appearance = NSApp.effectiveAppearance
        let labelCG = NSColor.labelColor.usingAppearance(appearance)
        let size = base.size
        let out = NSImage(size: size, flipped: false) { rect in
            labelCG.set()
            rect.fill()
            base.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
            return true
        }
        return out
    }
}

private extension NSColor {
    /// Resolve a dynamic color in the context of a specific NSAppearance.
    func usingAppearance(_ appearance: NSAppearance) -> NSColor {
        var resolved = self
        appearance.performAsCurrentDrawingAppearance {
            resolved = self.usingColorSpace(.deviceRGB) ?? self
        }
        return resolved
    }
}

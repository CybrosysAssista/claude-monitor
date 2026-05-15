const ExtensionUtils = imports.misc.extensionUtils;
const Me = ExtensionUtils.getCurrentExtension();

const { GLib, GObject, St, Clutter, Gio } = imports.gi;

const Main = imports.ui.main;
const PanelMenu = imports.ui.panelMenu;
const PopupMenu = imports.ui.popupMenu;


const {createScheduler, DEFAULT_POLL_INTERVAL_MS} = Me.imports.lib.core.scheduler;
const {createThresholdNotifier} = Me.imports.lib.core.notifications;
const {createClaudeProvider} = Me.imports.lib.providers.claude;
const {createCodexProvider} = Me.imports.lib.providers.codex;
const {readTextFile} = Me.imports.lib.runtime.fs;
const {createFetch} = Me.imports.lib.runtime.fetch;
const {buildUsageViewModel, PANEL_LABEL_MODES} = Me.imports.lib.ui.render;

// Map dot colors to hex-style CSS colors for inline style on percent label
const FILL_COLOR = {
    gray:    '#64748b',
    green:   '#10b981',
    emerald: '#34d399',
    yellow:  '#fbbf24',
    orange:  '#f97316',
    red:     '#ef4444',
};

// CSS class for the bar fill
const FILL_CLASSES = {
    gray:    'usage-fill-gray',
    green:   'usage-fill-green',
    emerald: 'usage-fill-emerald',
    yellow:  'usage-fill-yellow',
    orange:  'usage-fill-orange',
    red:     'usage-fill-red',
};

const PANEL_CLASSES = {
    gray:    'usage-panel-gray',
    green:   'usage-panel-green',
    emerald: 'usage-panel-emerald',
    yellow:  'usage-panel-yellow',
    orange:  'usage-panel-orange',
    red:     'usage-panel-red',
};

// Build one metric block: label + pct row, track, reset text
function createMetricWidgets() {
    const box = new St.BoxLayout({vertical: true, style_class: 'usage-metric'});
    box.set_x_expand(true);

    // Row: label left, pct right
    const mRow = new St.BoxLayout({style_class: 'usage-m-row'});
    mRow.set_x_expand(true);
    const mLabel = new St.Label({text: '--', style_class: 'usage-m-label'});
    mLabel.set_x_expand(false);
    const mPct = new St.Label({text: '--%', style_class: 'usage-m-pct'});
    mPct.set_x_expand(false);
    const mRowSpacer = new St.Widget();
    mRowSpacer.set_x_expand(true);
    mRow.add_child(mLabel);
    mRow.add_child(mRowSpacer);
    mRow.add_child(mPct);

    // Progress bar
    const track = new St.BoxLayout({style_class: 'usage-track'});
    track.set_x_expand(true);
    const fill = new St.Widget({style_class: 'usage-fill-gray'});
    fill._remainingPct = 0;
    track.add_child(fill);

    track.connect('notify::allocation', () => {
        const node = track.get_theme_node();
        if (!node) return;
        const cb = node.get_content_box(track.get_allocation_box());
        const w = cb.x2 - cb.x1;
        if (w > 0)
            fill.set_width(Math.round(w * fill._remainingPct / 100));
    });

    // Reset text (right-aligned)
    const mReset = new St.Label({text: '--', style_class: 'usage-m-reset'});
    mReset.set_x_expand(true);
    mReset.set_x_align(Clutter.ActorAlign.END);

    box.add_child(mRow);
    box.add_child(track);
    box.add_child(mReset);

    return {box, mLabel, mPct, track, fill, mReset};
}

// Build one service card (logo header + 2 metrics separated by a divider)
function createServiceCard(iconPath) {
    const card = new St.BoxLayout({vertical: true, style_class: 'usage-card'});
    card.set_x_expand(true);

    // Logo header
    const cardHead = new St.BoxLayout({style_class: 'usage-card-head'});
    cardHead.set_x_expand(true);

    try {
        const gicon = Gio.icon_new_for_string(iconPath);
        const logoWidget = new St.Icon({
            gicon,
            icon_size: 28,
            y_align: Clutter.ActorAlign.CENTER,
        });
        cardHead.add_child(logoWidget);
    } catch (_e) {
        const fallback = new St.Label({text: '●', style_class: 'usage-m-label'});
        cardHead.add_child(fallback);
    }
    card.add_child(cardHead);

    const metric0 = createMetricWidgets();
    const divider = new St.Widget({style_class: 'usage-divider'});
    divider.set_x_expand(true);
    const metric1 = createMetricWidgets();

    card.add_child(metric0.box);
    card.add_child(divider);
    card.add_child(metric1.box);

    return {card, metrics: [metric0, metric1]};
}

const MODE_LABELS = {
    'none':           'None (hide tray)',
    'overall':        'Overall (lowest %)',
    'all':            'All metrics',
    'claude':         'Claude',
    'claude-session': '    · Session',
    'claude-weekly':  '    · Weekly',
    'codex':          'Codex',
    'codex-session':  '    · Session',
    'codex-weekly':   '    · Weekly',
};

// Fine-grained leaf keys — these are what gets stored in GSettings
const FINE_KEYS = ['claude-session', 'claude-weekly', 'codex-session', 'codex-weekly'];
const CLAUDE_KEYS = ['claude-session', 'claude-weekly'];
const CODEX_KEYS  = ['codex-session', 'codex-weekly'];

// Which service icon to show in the tray for each mode
const MODE_SERVICE_MAP = {
    'min':            null,      // show both icons
    'claude-session': 'claude',
    'claude-weekly':  'claude',
    'codex-session':  'codex',
    'codex-weekly':   'codex',
};

const UsageIndicator = GObject.registerClass(
class UsageIndicator extends PanelMenu.Button {
    _init(scheduler, settings) {
        super._init(0.0, 'Usage Indicator');

        this._scheduler = scheduler;
        this._settings = settings;
        this._lastSummary = null;
        this._timerSourceId = 0;
        this._modeItems = [];
        this._trayWidgets = []; // track dynamically created tray children

        // Tray box: holds [icon label] [icon label] ... pairs
        this._trayBox = new St.BoxLayout({
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'usage-tray-box',
        });
        this.add_child(this._trayBox);

        this._buildPopup();
        this._startRelativeTimeTimer();

        this._settingsChangedId = this._settings.connect('changed::panel-label-modes', () => {
            this._updateOrnaments();
            this._refreshRelativeTimes();
        });
        this._invertChangedId = this._settings.connect('changed::display-inverted', () => {
            this._updateInvertOrnament();
            this._refreshRelativeTimes();
        });
    }

    _iconPath(name) {
        return Me.dir.get_child(`icons/${name}.svg`).get_path();
    }

    _buildPopup() {
        const menuItem = new PopupMenu.PopupBaseMenuItem({
            reactive: false,
            can_focus: false,
        });
        menuItem.set_x_expand(true);

        this._popupBox = new St.BoxLayout({
            vertical: true,
            style_class: 'usage-panel',
        });
        this._popupBox.set_x_expand(true);
        // Force the inner box to also take full width
        this._popupBox.set_x_align(Clutter.ActorAlign.FILL);

        // Codex card (index 0 in vm.services)
        this._codexCard = createServiceCard(this._iconPath('codex'));

        // Claude card (index 1 in vm.services)
        this._claudeCard = createServiceCard(this._iconPath('claude'));

        // Separator between the two cards
        const cardSep = new St.Widget({style_class: 'usage-card-separator'});
        cardSep.set_x_expand(true);

        // Footer
        const footer = new St.BoxLayout({style_class: 'usage-footer'});
        footer.set_x_expand(true);

        this._versionLabel = new St.Label({text: 'Claude Monitor 1.0.0', style_class: 'usage-footer-left'});
        this._nextUpdateLabel = new St.Label({text: 'Next update in --', style_class: 'usage-next'});
        const footerSpacer = new St.Widget();
        footerSpacer.set_x_expand(true);

        footer.add_child(this._versionLabel);
        footer.add_child(footerSpacer);
        footer.add_child(this._nextUpdateLabel);

        this._popupBox.add_child(this._claudeCard.card);
        this._popupBox.add_child(cardSep);
        this._popupBox.add_child(this._codexCard.card);
        this._popupBox.add_child(footer);

        menuItem.add_child(this._popupBox);
        this.menu.addMenuItem(menuItem);

        // Remove the left ornament gutter (the invisible dot space)
        // that PopupBaseMenuItem reserves even when no ornament is shown.
        if (menuItem._ornamentLabel)
            menuItem._ornamentLabel.set_width(0);

        // Separator + Refresh + Panel display
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const refreshItem = new PopupMenu.PopupMenuItem('↺  Refresh Now');
        this._refreshSignalId = refreshItem.connect('activate', () => {
            void this._scheduler?.refresh();
        });
        this._refreshItem = refreshItem;
        this.menu.addMenuItem(refreshItem);

        this._buildDisplaySubmenu();
    }

    _buildDisplaySubmenu() {
        this._displaySubmenu = new PopupMenu.PopupSubMenuMenuItem('Configure');
        this._modeItems = [];

        for (const mode of PANEL_LABEL_MODES) {
            const item = new PopupMenu.PopupMenuItem(MODE_LABELS[mode] ?? mode);
            item._modeKey = mode;
            item.connect('activate', () => this._onModeActivate(mode));
            this._modeItems.push(item);
            this._displaySubmenu.menu.addMenuItem(item);
        }

        this._displaySubmenu.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        this._invertItem = new PopupMenu.PopupMenuItem('↕  Reversed (% left)');
        this._invertItem.connect('activate', () => {
            const current = this._settings.get_boolean('display-inverted');
            this._settings.set_boolean('display-inverted', !current);
        });
        this._displaySubmenu.menu.addMenuItem(this._invertItem);

        this._updateOrnaments();
        this._updateInvertOrnament();
        this.menu.addMenuItem(this._displaySubmenu);
    }

    _updateInvertOrnament() {
        if (!this._invertItem) return;
        const inverted = this._settings.get_boolean('display-inverted');
        this._invertItem.setOrnament(inverted ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
    }

    _onModeActivate(mode) {
        const current = this._settings.get_strv('panel-label-modes');

        // ── None: exclusive, hides tray ───────────────────────────────
        if (mode === 'none') {
            this._settings.set_strv('panel-label-modes', ['none']);
            return;
        }

        // ── Overall: exclusive reset ──────────────────────────────────
        if (mode === 'overall') {
            this._settings.set_strv('panel-label-modes', ['overall']);
            return;
        }

        // ── All: exclusive, selects all 4 fine-grained keys ──────────
        if (mode === 'all') {
            const allSelected = FINE_KEYS.every(k => current.includes(k));
            this._settings.set_strv('panel-label-modes',
                allSelected ? ['overall'] : [...FINE_KEYS]);
            return;
        }

        // ── Group (claude / codex): batch toggle ──────────────────────
        const groupKeys = mode === 'claude' ? CLAUDE_KEYS : mode === 'codex' ? CODEX_KEYS : null;
        if (groupKeys) {
            const allIn = groupKeys.every(k => current.includes(k));
            let next = current.filter(k => k !== 'overall' && k !== 'none');
            if (allIn) {
                next = next.filter(k => !groupKeys.includes(k));
            } else {
                for (const k of groupKeys) {
                    if (!next.includes(k)) next.push(k);
                }
            }
            if (next.length === 0) next = ['overall'];
            this._settings.set_strv('panel-label-modes', next);
            return;
        }

        // ── Fine-grained (claude-session etc.): individual toggle ─────
        let next = current.filter(k => k !== 'overall' && k !== 'none');
        if (next.includes(mode)) {
            next = next.filter(k => k !== mode);
        } else {
            next = [...next, mode];
        }
        if (next.length === 0) next = ['overall'];
        this._settings.set_strv('panel-label-modes', next);
    }

    _updateOrnaments() {
        const current = this._settings.get_strv('panel-label-modes');
        const isNone      = current.includes('none');
        const hasFine     = !isNone && current.some(k => FINE_KEYS.includes(k));
        const allClaudeIn = CLAUDE_KEYS.every(k => current.includes(k));
        const allCodexIn  = CODEX_KEYS.every(k => current.includes(k));
        const allFineIn   = FINE_KEYS.every(k => current.includes(k));

        for (const item of this._modeItems) {
            const key = item._modeKey;
            let checked = false;

            switch (key) {
                case 'none':
                    checked = isNone;
                    break;
                case 'overall':
                    checked = !isNone && !hasFine;
                    break;
                case 'all':
                    checked = allFineIn;
                    break;
                case 'claude':
                    checked = allClaudeIn;
                    break;
                case 'codex':
                    checked = allCodexIn;
                    break;
                case 'claude-session':
                case 'claude-weekly':
                    checked = current.includes(key) && !allClaudeIn;
                    break;
                case 'codex-session':
                case 'codex-weekly':
                    checked = current.includes(key) && !allCodexIn;
                    break;
            }

            item.setOrnament(checked ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
        }
    }

    _startRelativeTimeTimer() {
        this._timerSourceId = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT,
            60,
            () => {
                this._refreshRelativeTimes();
                return GLib.SOURCE_CONTINUE;
            },
        );
    }

    _refreshRelativeTimes() {
        if (!this._lastSummary)
            return;

        this._applyViewModel(buildUsageViewModel(this._lastSummary, {
            now: Date.now(),
            pollIntervalMs: DEFAULT_POLL_INTERVAL_MS,
            panelLabelModes: this._settings.get_strv('panel-label-modes'),
            displayInverted: this._settings.get_boolean('display-inverted'),
        }));
    }

    render(summary) {
        this._lastSummary = summary;
        this._applyViewModel(buildUsageViewModel(summary, {
            now: Date.now(),
            pollIntervalMs: DEFAULT_POLL_INTERVAL_MS,
            panelLabelModes: this._settings.get_strv('panel-label-modes'),
            displayInverted: this._settings.get_boolean('display-inverted'),
        }));
    }

    _applyMetric(metric, w) {
        metric.mLabel.text = w.label;
        metric.mPct.text = w.remainingText;

        // Inline color on the pct label via style
        const col = FILL_COLOR[w.dotColor] ?? '#ef4444';
        metric.mPct.set_style(`color: ${col};`);

        const fillClass = FILL_CLASSES[w.dotColor] ?? 'usage-fill-red';
        metric.fill.style_class = fillClass;
        metric.fill._remainingPct = w.fillPct;
        metric.mReset.text = w.resetsInText;

        const node = metric.track.get_theme_node();
        if (node) {
            const cb = node.get_content_box(metric.track.get_allocation_box());
            const tw = cb.x2 - cb.x1;
            if (tw > 0)
                metric.fill.set_width(Math.round(tw * w.fillPct / 100));
        }
    }

    _rebuildTray(vm) {
        // Remove all previous tray children
        for (const w of this._trayWidgets)
            this._trayBox.remove_child(w);
        this._trayWidgets = [];

        // vm.panelEntries = [{mode, text, color, icon}]
        const entries = vm.panelEntries ?? [];

        // 'none' mode — no entries; show a muted dash so the button stays clickable
        if (entries.length === 0) {
            const lbl = new St.Label({
                text: '–',
                y_align: Clutter.ActorAlign.CENTER,
                style_class: 'usage-panel-gray',
            });
            this._trayBox.add_child(lbl);
            this._trayWidgets.push(lbl);
            return;
        }

        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];

            // Separator dot between entries (except first)
            if (i > 0) {
                const sep = new St.Label({
                    text: ' · ',
                    y_align: Clutter.ActorAlign.CENTER,
                    style_class: 'usage-panel-gray',
                });
                this._trayBox.add_child(sep);
                this._trayWidgets.push(sep);
            }

            // Service icon (claude / codex), or both for 'min'
            if (entry.mode === 'min') {
                // Show both icons side by side for the global minimum
                for (const svc of ['codex', 'claude']) {
                    const icon = this._makeTrayIcon(svc, 14);
                    this._trayBox.add_child(icon);
                    this._trayWidgets.push(icon);
                }
            } else if (entry.icon) {
                const icon = this._makeTrayIcon(entry.icon, 14);
                this._trayBox.add_child(icon);
                this._trayWidgets.push(icon);
            }

            // Percentage label — colored by THIS entry's own usage level
            const lbl = new St.Label({
                text: ` ${entry.text}`,
                y_align: Clutter.ActorAlign.CENTER,
                style_class: PANEL_CLASSES[entry.color] ?? 'usage-panel-gray',
            });
            this._trayBox.add_child(lbl);
            this._trayWidgets.push(lbl);
        }
    }

    _makeTrayIcon(svcName, size) {
        try {
            const gicon = Gio.icon_new_for_string(this._iconPath(svcName));
            return new St.Icon({
                gicon,
                icon_size: size,
                y_align: Clutter.ActorAlign.CENTER,
            });
        } catch (_e) {
            return new St.Label({
                text: svcName === 'claude' ? '◆' : '⬡',
                y_align: Clutter.ActorAlign.CENTER,
            });
        }
    }

    _applyViewModel(vm) {
        this._rebuildTray(vm);

        // vm.services[0] = Codex, vm.services[1] = Claude
        const cards = [this._codexCard, this._claudeCard];
        for (let i = 0; i < vm.services.length; i++) {
            const svc = vm.services[i];
            const card = cards[i];
            for (let j = 0; j < svc.windows.length; j++) {
                this._applyMetric(card.metrics[j], svc.windows[j]);
            }
        }

        this._versionLabel.text = vm.version;
        this._nextUpdateLabel.text = vm.lastUpdate;
    }

    destroy() {
        if (this._timerSourceId) {
            GLib.source_remove(this._timerSourceId);
            this._timerSourceId = 0;
        }

        if (this._refreshSignalId && this._refreshItem) {
            this._refreshItem.disconnect(this._refreshSignalId);
            this._refreshSignalId = null;
        }

        if (this._settingsChangedId && this._settings) {
            this._settings.disconnect(this._settingsChangedId);
            this._settingsChangedId = null;
        }

        if (this._invertChangedId && this._settings) {
            this._settings.disconnect(this._invertChangedId);
            this._invertChangedId = null;
        }

        this._settings = null;
        super.destroy();
    }
});

class UsageLimitsExtension {
    constructor() {
        this.uuid = Me.metadata.uuid;
    }
    getSettings() {
        return ExtensionUtils.getSettings(Me.metadata['settings-schema']);
    }
    enable() {
        this._fetchRuntime = createFetch();
        const fetchImpl = this._fetchRuntime.fetch;
        const fileReader = readTextFile;

        const claude = createClaudeProvider({
            fetch: fetchImpl,
            readTextFile: fileReader,
        });
        const codex = createCodexProvider({
            fetch: fetchImpl,
            readTextFile: fileReader,
        });
        this._thresholdNotifier = createThresholdNotifier({
            notifyFn: (title, body) => {
                Main.notify(title, body);
            },
        });

        this._scheduler = createScheduler({
            providers: {claude, codex},
            onUpdate: (summary) => {
                this._indicator?.render(summary);
                this._thresholdNotifier?.evaluate(summary);
            },
        });

        this._settings = this.getSettings();
        this._indicator = new UsageIndicator(this._scheduler, this._settings);
        Main.panel.addToStatusArea(this.uuid, this._indicator);
        this._scheduler.start();
    }

    disable() {
        this._scheduler?.stop();
        this._scheduler = null;
        this._thresholdNotifier = null;

        this._fetchRuntime?.dispose();
        this._fetchRuntime = null;

        if (!this._indicator)
            return;

        this._indicator.destroy();
        this._indicator = null;
        this._settings = null;
    }
}

function init() {
    return new UsageLimitsExtension();
}

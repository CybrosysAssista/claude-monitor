const VERSION = 'Claude Monitor 1.0.0';

// All user-facing mode keys (high-level + fine-grained)
var PANEL_LABEL_MODES = [
    'none',
    'overall',
    'all',
    'claude',
    'claude-session',
    'claude-weekly',
    'codex',
    'codex-session',
    'codex-weekly',
];

// Fine-grained stored keys (never 'all', 'claude', 'codex' stored directly)
const FINE_GRAINED = ['claude-session', 'claude-weekly', 'codex-session', 'codex-weekly'];

// Expand a high-level mode to internal specific modes
function expandMode(mode) {
    switch (mode) {
        case 'none':    return [];           // no tray entries
        case 'overall': return ['min'];
        case 'all':     return FINE_GRAINED.slice();
        case 'claude':  return ['claude-session', 'claude-weekly'];
        case 'codex':   return ['codex-session', 'codex-weekly'];
        // Fine-grained modes and 'min' pass through directly
        case 'min':     return ['min'];
        default:        return [mode];
    }
}

function getPanelLabelValue(summary, mode) {
    if (mode === 'min' || !mode)
        return summary?.minRemainingPct;

    const providers = summary?.providers;
    if (!providers)
        return undefined;

    switch (mode) {
        case 'claude-session': return providers.claude?.data?.sessionRemainingPct;
        case 'claude-weekly':  return providers.claude?.data?.weeklyRemainingPct;
        case 'codex-session':  return providers.codex?.data?.sessionRemainingPct;
        case 'codex-weekly':   return providers.codex?.data?.weeklyRemainingPct;
        default: return summary?.minRemainingPct;
    }
}

// Tray label: "S:" for session, "W:" for weekly, blank for overall
const MODE_LABEL = {
    'min':            '',
    'claude-session': 'S:',
    'claude-weekly':  'W:',
    'codex-session':  'S:',
    'codex-weekly':   'W:',
};

// Which service icon for each specific mode
const MODE_ICON = {
    'min':            null,      // both icons shown
    'claude-session': 'claude',
    'claude-weekly':  'claude',
    'codex-session':  'codex',
    'codex-weekly':   'codex',
};

function buildPanelColor(summary, specificModes) {
    if (!Array.isArray(specificModes) || specificModes.length === 0)
        return getDotColor(summary?.minRemainingPct);

    // Use the worst (lowest) color across all entries
    const ORDER = ['green', 'emerald', 'yellow', 'orange', 'red', 'gray'];
    let worst = 'green';
    for (const mode of specificModes) {
        const val = getPanelLabelValue(summary, mode);
        const color = getDotColor(val);
        if (ORDER.indexOf(color) > ORDER.indexOf(worst))
            worst = color;
    }
    return worst;
}

function formatPercent(value, inverted = false) {
    if (!Number.isFinite(value))
        return '--';

    const pct = inverted ? Math.round(value) : Math.round(100 - value);
    return `${pct}%`;
}

var getDotColor = function(pct) {
    if (!Number.isFinite(pct))
        return 'gray';

    if (pct >= 80)
        return 'green';

    if (pct >= 50)
        return 'emerald';

    if (pct >= 30)
        return 'yellow';

    if (pct >= 15)
        return 'orange';

    return 'red';
}

var formatRelativeTime = function(iso, now) {
    if (!iso)
        return '--';

    const target = new Date(iso).getTime();
    if (Number.isNaN(target))
        return '--';

    const diffMs = target - now;
    if (diffMs <= 0)
        return '--';

    const totalMinutes = Math.floor(diffMs / 60_000);
    const days = Math.floor(totalMinutes / (60 * 24));
    const hours = Math.floor((totalMinutes % (60 * 24)) / 60);
    const minutes = totalMinutes % 60;

    const parts = [];
    if (days > 0)
        parts.push(`${days}d`);

    if (hours > 0)
        parts.push(`${hours}h`);

    if (minutes > 0 || parts.length === 0)
        parts.push(`${minutes}m`);

    return parts.join(' ');
}

function formatRemainingText(pct, inverted = false) {
    if (!Number.isFinite(pct))
        return inverted ? '-- left' : '-- used';

    return inverted
        ? `${Math.round(pct)}% left`
        : `${Math.round(100 - pct)}% used`;
}

function formatResetsIn(iso, now) {
    const rel = formatRelativeTime(iso, now);
    if (rel === '--')
        return '--';

    return `Resets in ${rel}`;
}

function toWarningText(providerLabel, code) {
    if (code === 'AUTH_EXPIRED')
        return `${providerLabel}: authentication expired`;

    if (code === 'PARTIAL_DATA')
        return `${providerLabel}: partial usage data`;

    if (code === 'NETWORK_ERROR')
        return `${providerLabel}: network error`;

    if (code === 'SCHEMA_CHANGED')
        return `${providerLabel}: schema changed`;

    if (code === 'MISSING_CREDS')
        return `${providerLabel}: missing credentials`;

    return '';
}

function buildWindowViewModel(label, remainingPct, resetsAtIso, now, inverted = false) {
    const safeRemaining = Number.isFinite(remainingPct) ? Math.round(remainingPct) : 0;
    return {
        label,
        remainingPct: safeRemaining,
        fillPct: inverted ? safeRemaining : Math.round(100 - safeRemaining),
        remainingText: formatRemainingText(remainingPct, inverted),
        resetsInText: formatResetsIn(resetsAtIso, now),
        dotColor: getDotColor(remainingPct),
    };
}

function buildServiceViewModel(name, providerData, providerCode, now, inverted = false) {
    const data = providerData ?? null;

    return {
        name,
        windows: [
            buildWindowViewModel(
                'Session',
                data?.sessionRemainingPct,
                data?.sessionResetsAtIso,
                now,
                inverted,
            ),
            buildWindowViewModel(
                'Weekly',
                data?.weeklyRemainingPct,
                data?.weeklyResetsAtIso,
                now,
                inverted,
            ),
        ],
        warning: toWarningText(name, providerCode),
    };
}

function formatNextUpdate(lastUpdatedAtIso, pollIntervalMs, now) {
    if (!lastUpdatedAtIso || !Number.isFinite(pollIntervalMs))
        return 'Next update in --';

    const lastMs = new Date(lastUpdatedAtIso).getTime();
    if (Number.isNaN(lastMs))
        return 'Next update in --';

    const nextMs = lastMs + pollIntervalMs;
    const diffMs = nextMs - now;

    if (diffMs <= 0)
        return 'Next update in 0m';

    const totalMinutes = Math.max(1, Math.ceil(diffMs / 60_000));
    return `Next update in ${totalMinutes}m`;
}

var buildUsageViewModel = function(summary, deps = {}) {
    const now = deps.now ?? Date.now();
    const version = deps.version ?? VERSION;
    const pollIntervalMs = deps.pollIntervalMs ?? 180_000;
    const inverted = deps.displayInverted ?? false;

    // Accept both old single string and new array; default to 'overall'
    let userModes = deps.panelLabelModes ?? deps.panelLabelMode ?? ['overall'];
    if (typeof userModes === 'string')
        userModes = [userModes];

    // Expand each high-level mode to its specific internal modes
    const specificModes = userModes.flatMap(m => expandMode(m));

    const claude = summary?.providers?.claude ?? null;
    const codex = summary?.providers?.codex ?? null;

    // Build per-entry data for the tray: each specific mode gets its own label, color, icon
    const panelEntries = specificModes.map(mode => {
        const val = getPanelLabelValue(summary, mode);
        const label = MODE_LABEL[mode] ?? '';
        const pct = formatPercent(val, inverted);
        // Format: "S: 85%" / "W: 60%" / "85%" (for overall/min)
        const text = label ? `${label} ${pct}` : pct;
        return {
            mode,
            text,
            color: getDotColor(val),
            icon: MODE_ICON[mode] ?? null,
        };
    });

    return {
        panelColor: buildPanelColor(summary, specificModes),
        panelEntries,
        services: [
            buildServiceViewModel('Codex', codex?.data, codex?.code, now, inverted),
            buildServiceViewModel('Claude', claude?.data, claude?.code, now, inverted),
        ],
        version,
        lastUpdate: formatNextUpdate(summary?.lastUpdatedAtIso, pollIntervalMs, now),
    };
}

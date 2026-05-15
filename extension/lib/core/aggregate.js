const ExtensionUtils = imports.misc.extensionUtils;
const Me = ExtensionUtils.getCurrentExtension();

const {snapshotProviderState} = Me.imports.lib.core.state;

function collectRemainingPercentages(data) {
    if (!data || typeof data !== 'object')
        return [];

    const values = [];

    for (const [key, value] of Object.entries(data)) {
        if (!key.endsWith('RemainingPct'))
            continue;

        if (!Number.isFinite(value))
            continue;

        values.push(value);
    }

    return values;
}

var computeSummary = function(providerStates) {
    const providers = {};
    const remainingPercentages = [];
    let latestTimestamp = null;

    for (const [name, state] of providerStates.entries()) {
        const snapshot = snapshotProviderState(state);
        providers[name] = snapshot;
        remainingPercentages.push(...collectRemainingPercentages(snapshot.data));

        if (snapshot.lastUpdatedAtIso && (!latestTimestamp || snapshot.lastUpdatedAtIso > latestTimestamp))
            latestTimestamp = snapshot.lastUpdatedAtIso;
    }

    const minRemainingPct = remainingPercentages.length > 0
        ? Math.min(...remainingPercentages)
        : null;

    return {
        providers,
        minRemainingPct,
        lastUpdatedAtIso: latestTimestamp,
    };
}

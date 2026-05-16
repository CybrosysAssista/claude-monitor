const ExtensionUtils = imports.misc.extensionUtils;
const Me = ExtensionUtils.getCurrentExtension();

const {computeSummary} = Me.imports.lib.core.aggregate;
const {createBackoffManager} = Me.imports.lib.core.backoff;
const {applyProviderResult, createProviderState} = Me.imports.lib.core.state;

var DEFAULT_POLL_INTERVAL_MS = 180_000;

function normalizeProviders(providersInput) {
    if (Array.isArray(providersInput)) {
        return providersInput.map((provider, index) => {
            const name = provider?.name ?? `provider_${index}`;
            return {name, provider};
        });
    }

    if (providersInput && typeof providersInput === 'object') {
        return Object.entries(providersInput).map(([name, provider]) => ({name, provider}));
    }

    return [];
}

function createNetworkFailureResult() {
    return {
        ok: false,
        error: {
            code: 'network_error',
            message: 'Provider request threw before returning a result',
        },
    };
}

var createScheduler = function(options = {}) {
    const providers = normalizeProviders(options.providers);
    const pollIntervalMs = options.pollIntervalMs ?? DEFAULT_POLL_INTERVAL_MS;
    const nowIso = options.nowIso ?? (() => new Date().toISOString());
    const onUpdate = options.onUpdate ?? null;
    const setIntervalFn = options.setIntervalFn ?? globalThis.setInterval;
    const clearIntervalFn = options.clearIntervalFn ?? globalThis.clearInterval;
    const backoffManager = options.backoffManager ?? createBackoffManager();
    const providerStates = new Map();

    for (const {name} of providers)
        providerStates.set(name, createProviderState(name));

    let timerId = null;

    function notify() {
        if (typeof onUpdate !== 'function')
            return;

        onUpdate(computeSummary(providerStates));
    }

    function queueProviderRequest(name, provider) {
        const state = providerStates.get(name);
        if (!state || !provider || typeof provider.getUsage !== 'function')
            return Promise.resolve();

        if (backoffManager.shouldBackoff(name))
            return Promise.resolve();

        const requestId = state.latestRequestedRequestId + 1;
        state.latestRequestedRequestId = requestId;

        state.queue = state.queue.then(async () => {
            state.inFlight = true;
            notify();

            let result;

            try {
                result = await provider.getUsage();
            } catch {
                result = createNetworkFailureResult();
            }

            applyProviderResult(state, result, requestId, nowIso());
            backoffManager.recordResult(name, result);
            state.inFlight = false;
            notify();
        });

        return state.queue;
    }

    async function refresh() {
        const runs = providers.map(({name, provider}) => queueProviderRequest(name, provider));
        await Promise.all(runs);
        return getSummary();
    }

    function start() {
        if (timerId)
            return;

        timerId = setIntervalFn(() => {
            void refresh();
        }, pollIntervalMs);

        void refresh();
    }

    function stop() {
        if (!timerId)
            return;

        clearIntervalFn(timerId);
        timerId = null;
    }

    function getSummary() {
        return computeSummary(providerStates);
    }

    return {
        start,
        stop,
        refresh,
        getSummary,
    };
}

if (typeof module !== 'undefined') {
    module.exports = {createScheduler, DEFAULT_POLL_INTERVAL_MS};
}

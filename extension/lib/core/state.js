var PROVIDER_STATE_CODES = {
    OK: 'OK',
    PARTIAL_DATA: 'PARTIAL_DATA',
    AUTH_EXPIRED: 'AUTH_EXPIRED',
    RATE_LIMITED: 'RATE_LIMITED',
    NETWORK_ERROR: 'NETWORK_ERROR',
    SCHEMA_CHANGED: 'SCHEMA_CHANGED',
    MISSING_CREDS: 'MISSING_CREDS',
};

const ERROR_CODE_MAP = {
    partial_data: PROVIDER_STATE_CODES.PARTIAL_DATA,
    auth_expired: PROVIDER_STATE_CODES.AUTH_EXPIRED,
    rate_limited: PROVIDER_STATE_CODES.RATE_LIMITED,
    network_error: PROVIDER_STATE_CODES.NETWORK_ERROR,
    schema_changed: PROVIDER_STATE_CODES.SCHEMA_CHANGED,
    parse_error: PROVIDER_STATE_CODES.SCHEMA_CHANGED,
    missing_creds: PROVIDER_STATE_CODES.MISSING_CREDS,
};

function toMappedCode(result) {
    if (result?.ok)
        return PROVIDER_STATE_CODES.OK;

    const mapped = ERROR_CODE_MAP[result?.error?.code];
    if (mapped)
        return mapped;

    return PROVIDER_STATE_CODES.SCHEMA_CHANGED;
}

var createProviderState = function(name) {
    return {
        name,
        inFlight: false,
        latestRequestedRequestId: 0,
        latestAppliedRequestId: 0,
        code: null,
        data: null,
        error: null,
        lastUpdatedAtIso: null,
        queue: Promise.resolve(),
    };
}

var applyProviderResult = function(state, result, requestId, updatedAtIso) {
    if (requestId < state.latestAppliedRequestId)
        return false;

    state.latestAppliedRequestId = requestId;
    state.code = toMappedCode(result);
    state.lastUpdatedAtIso = updatedAtIso;

    if (result?.ok) {
        state.data = result.data ?? null;
        state.error = null;
        return true;
    }

    state.data = result?.data ?? null;
    state.error = {
        code: state.code,
        providerCode: result?.error?.code ?? null,
        message: result?.error?.message ?? null,
    };

    return true;
}

var snapshotProviderState = function(state) {
    return {
        code: state.code,
        data: state.data,
        error: state.error,
        inFlight: state.inFlight,
        lastUpdatedAtIso: state.lastUpdatedAtIso,
    };
}

if (typeof module !== 'undefined') {
    module.exports = {PROVIDER_STATE_CODES, createProviderState, applyProviderResult, snapshotProviderState};
}

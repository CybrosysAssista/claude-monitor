// CJS shim — sets up globalThis.imports so GJS-style extension files can be
// loaded by bun's test runner without a real GNOME Shell runtime.
// Loaded via bunfig.toml [test] preload before any test file runs.

// Step 1: load pure modules (no imports.* references at top level)
const backoff       = require('../../extension/lib/core/backoff.js');
const normalize     = require('../../extension/lib/core/normalize.js');
const state         = require('../../extension/lib/core/state.js');
const notifications = require('../../extension/lib/core/notifications.js');
const render        = require('../../extension/lib/ui/render.js');

// Step 2: build the mock Me object with what we have so far
const mockLibCore = {
    backoff,
    normalize,
    state,
    aggregate: {},   // placeholder — filled after aggregate.js is loaded
};

const mockMe = {
    imports: {
        lib: {
            core: mockLibCore,
        },
    },
};

// Step 3: install globalThis.imports — must be done before loading files that
// call imports.gi / imports.misc at module scope
globalThis.imports = {
    gi: {
        GLib: {
            get_home_dir: () => process.env.HOME || '/home/testuser',
        },
    },
    misc: {
        extensionUtils: {
            getCurrentExtension: () => mockMe,
        },
    },
};

// Step 4: load aggregate (uses imports.misc → state)
const aggregate = require('../../extension/lib/core/aggregate.js');
mockLibCore.aggregate = aggregate;

// Step 5: load scheduler (uses imports.misc → aggregate, backoff, state)
require('../../extension/lib/core/scheduler.js');

// Step 6: load providers (use imports.gi.GLib + imports.misc → normalize)
require('../../extension/lib/providers/claude.js');
require('../../extension/lib/providers/codex.js');

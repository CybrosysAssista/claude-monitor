# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

GNOME Shell 45/46 extension that polls Claude (Anthropic) and Codex (OpenAI) OAuth APIs for usage limits and displays remaining percentages in the top panel with threshold notifications.

## Repository

- GitHub: https://github.com/CybrosysAssista/claude-monitor
- `gh release create v<X.Y.Z> claudemonitor@assista.shell-extension.zip --title "v<X.Y.Z>" --notes "..."` — publish release

## Commands

```bash
bun test                        # Run all unit tests
bun test test/unit/scheduler.test.js  # Run a single test file
bash scripts/dev/pack.sh        # Pack .shell-extension.zip
bash scripts/dev/install.sh     # Install extension locally (calls pack if needed)
# GOTCHA: install.sh skips pack if zip already exists — always run pack.sh first after code changes
# GOTCHA: gnome-extensions pack only includes top-level files — lib/ requires --extra-source=lib in pack.sh
bash scripts/dev/enable.sh      # gnome-extensions enable claudemonitor@assista
bash scripts/dev/disable.sh     # gnome-extensions disable claudemonitor@assista
journalctl --user -f /usr/bin/gnome-shell  # Live extension logs
```

After changing extension source, must re-install and re-login (Wayland) or `Alt+F2 → r` (X11) for GNOME Shell to pick up changes.

## Architecture

```
extension.js          → GNOME lifecycle (enable/disable), wires DI, GObject UI
lib/core/scheduler.js → Polls providers on 180s interval, serial queue per provider
lib/core/aggregate.js → Computes minRemainingPct across all providers
lib/core/state.js     → Per-provider state machine (OK/PARTIAL_DATA/AUTH_EXPIRED/RATE_LIMITED/NETWORK_ERROR/SCHEMA_CHANGED)
lib/core/backoff.js   → Exponential backoff (30s initial, 15m cap, triggers on 2+ consecutive network errors or 429)
lib/core/notifications.js → Fires Main.notify() when usage crosses below 20%, deduplicates per window
lib/core/normalize.js → Extracts remaining% from Claude/Codex API response shapes
lib/providers/claude.js → OAuth refresh + usage fetch against api.anthropic.com
lib/providers/codex.js  → OAuth refresh + usage fetch against chatgpt.com
lib/runtime/fetch.js  → Soup 3.0 async HTTP wrapped in Promises
lib/runtime/fs.js     → Gio async file read wrapped in Promises
lib/ui/render.js      → Pure function: summary → UI view model strings
```

## GSettings

- Schema XML lives in `extension/schemas/`, compiled automatically by `gnome-extensions pack --schema=...`
- `this.getSettings()` in Extension subclass loads schema by `settings-schema` from `metadata.json`
- After adding/changing schema: must repack, reinstall, and re-login

## Key Patterns

- **St.Widget sizing in popups**: `widget.get_width()` returns 0 when popup is closed. Store data on widget (e.g. `fill._remainingPct`) and use `notify::allocation` to recalculate when popup opens.
- **Dependency injection everywhere**: All modules export factory functions (`createScheduler`, `createClaudeProvider`, etc.) that receive deps as options. This is how tests work without GJS runtime.
- **Provider interface contract**: `{getUsage(): Promise<{ok, data?, error?}>}`. Adding a new provider means implementing this shape and registering in scheduler.
- **GObject.registerClass()**: Required for any class extending PanelMenu.Button or other GObject types. Use `_init()` not `constructor()`, `super._init()` not `super()`.
- **Result type**: `{ok: boolean, data?: {...}, error?: {code: string, message: string}}` — used by providers, state, and scheduler.
- **Serial request queue**: One in-flight request per provider via Promise chain — never parallel requests to same API.

## Testing

Tests use `bun:test` (describe/test/expect + vi for fake timers). Tests mock fetch and readTextFile via DI — no network or filesystem calls. Scheduler tests use `vi.useFakeTimers()` and `vi.advanceTimersByTime()` to control polling. Provider tests use deferred promises to simulate async resolution order.

## Credentials

- Claude: `~/.claude/.credentials.json` → `claudeAiOauth.{accessToken, refreshToken, expiresAt}`
- Codex: `~/.codex/auth.json` → `tokens.{access_token, refresh_token, account_id}`

Both providers support multiple field naming conventions (camelCase and snake_case).

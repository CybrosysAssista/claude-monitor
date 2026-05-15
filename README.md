# Claude Monitor

> GNOME Shell extension that shows Claude and Codex AI usage limits directly in your top panel — no browser tab needed.

![GNOME Shell 45–49](https://img.shields.io/badge/GNOME_Shell-45--49-4A90D9?style=flat-square)
![License: MIT](https://img.shields.io/badge/License-MIT-22c55e?style=flat-square)
![Author: CybrosysAssista](https://img.shields.io/badge/Author-CybrosysAssista-8b5cf6?style=flat-square)

---

![Claude Monitor popup](assets/preview.png)

---

## What makes this different

Most usage trackers show a single number. Claude Monitor shows **each limit independently** — session and weekly, per provider — with individual progress bars, reset countdowns, and colors that reflect each window's own health. You can also flip the entire display between **% used** and **% left** with one click.

Key features not found in typical extensions:

- **5-level color scale** — green / emerald / yellow / orange / red, each tied to a specific threshold
- **Per-entry tray coloring** — every metric in the panel bar has its own color, not a single blended one
- **Service icons in tray** — Claude and Codex SVG icons appear inline next to each label
- **9 configurable display modes** — from a single overall minimum to per-window fine-grained labels, shown side by side
- **Group toggles** — selecting "Claude" in Configure toggles both session + weekly at once
- **% used ↔ % left toggle** — GSettings-persisted, survives GNOME restarts
- **Desktop notifications** when any window crosses below 20%, deduplicated per reset window
- **Manual refresh** button in the popup

---

## Color thresholds

| Remaining | Color |
|-----------|-------|
| ≥ 80% | 🟢 Green |
| 50 – 79% | 🟩 Emerald |
| 30 – 49% | 🟡 Yellow |
| 15 – 29% | 🟠 Orange |
| < 15% | 🔴 Red |

---

## Requirements

- GNOME Shell 45–49
- Credentials on disk from the respective CLI tools:

| Provider | Credential file |
|----------|----------------|
| Claude | `~/.claude/.credentials.json` |
| Codex | `~/.codex/auth.json` |

Credentials are written automatically when you sign in via [Claude Code](https://docs.anthropic.com/en/docs/claude-code) or [Codex CLI](https://github.com/openai/codex).

---

## Installation

**From GitHub Releases**

```bash
# Download claudemonitor@assista.shell-extension.zip from Releases, then:
gnome-extensions install --force claudemonitor@assista.shell-extension.zip

# Restart GNOME Shell
# Wayland: log out → log back in
# X11: Alt+F2 → r → Enter

gnome-extensions enable claudemonitor@assista
```

**From source**

```bash
git clone git@github.com:CybrosysAssista/claude-monitor.git
cd claude-monitor
bash scripts/dev/pack.sh
bash scripts/dev/install.sh
bash scripts/dev/enable.sh
```

---

## Panel display modes

Open the popup → **Configure** to choose what the top-bar label shows:

| Mode | What it displays |
|------|-----------------|
| Overall (lowest %) | Single number — worst across all windows |
| All metrics | One label per window, side by side |
| Claude | Both Claude windows |
| Claude · Session | Claude session only |
| Claude · Weekly | Claude weekly only |
| Codex | Both Codex windows |
| Codex · Session | Codex session only |
| Codex · Weekly | Codex weekly only |
| None | Hides the tray label (popup still works) |

Toggle **Reversed (% left)** to flip between "% used" (default) and "% left".

---

## Architecture

```
extension.js                 — GNOME lifecycle, GObject UI, wires DI
extension/lib/
  core/
    scheduler.js             — polls providers every 180 s, serial queue per provider
    aggregate.js             — derives minRemainingPct across all providers
    state.js                 — per-provider state machine (OK / AUTH_EXPIRED / RATE_LIMITED / …)
    backoff.js               — exponential backoff: 30 s → 15 min cap on network errors / 429s
    notifications.js         — fires GNOME notify() below 20%, deduplicates per reset window
    normalize.js             — extracts remaining % from Claude / Codex API shapes
  providers/
    claude.js                — OAuth refresh + usage fetch → api.anthropic.com
    codex.js                 — OAuth refresh + usage fetch → chatgpt.com
  runtime/
    fetch.js                 — Soup 3.0 async HTTP wrapped in Promises
    fs.js                    — Gio async file read wrapped in Promises
  ui/
    render.js                — pure function: summary → view-model strings
extension/schemas/           — GSettings schema (display-inverted, panel-label-modes)
extension/icons/             — claude.svg, codex.svg
test/unit/                   — bun:test unit tests, all I/O mocked via DI
```

---

## Development

```bash
npx bun test                              # run unit tests
bash scripts/dev/pack.sh                  # build claudemonitor@assista.shell-extension.zip
bash scripts/dev/install.sh               # install locally (runs pack if zip missing)
bash scripts/dev/enable.sh                # enable extension
journalctl --user -f /usr/bin/gnome-shell # live logs
```

> After any source change: `pack.sh` → `install.sh` → restart GNOME Shell (re-login on Wayland).

---

## License

MIT © 2026 CybrosysAssista

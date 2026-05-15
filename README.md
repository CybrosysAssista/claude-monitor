# Claude Monitor

> Track your Claude and Codex AI usage limits directly in the GNOME system tray — real-time, at a glance, no browser needed.

![GNOME Shell 45–49](https://img.shields.io/badge/GNOME_Shell-45--49-4A90D9?style=flat-square)
![License: MIT](https://img.shields.io/badge/License-MIT-22c55e?style=flat-square)
![Author: CybrosysAssista](https://img.shields.io/badge/Author-CybrosysAssista-8b5cf6?style=flat-square)

---

![Claude Monitor popup](assets/preview.png)

---

## Overview

Claude Monitor is a GNOME Shell extension that polls the Claude (Anthropic) and Codex (OpenAI) OAuth APIs every 3 minutes and displays live usage percentages in the system tray. Click the tray indicator to open a detailed popup with per-provider progress bars, reset timers, and status colors.

Session and weekly limits are tracked independently for each provider. The tray label updates automatically and can be configured to show exactly what matters to you.

---

## Features

- **System tray indicator** — live usage percentage always visible in the GNOME top bar
- **Per-provider, per-window tracking** — session and weekly limits shown separately for Claude and Codex
- **5-level color scale** — green / emerald / yellow / orange / red, each tied to a specific usage threshold
- **Per-entry tray coloring** — each metric in the tray bar carries its own color
- **Service icons in tray** — Claude and Codex SVG icons shown inline next to each label
- **9 configurable display modes** — overall minimum, per-provider, per-window, or all side by side
- **Group toggles** — selecting Claude or Codex in Configure toggles both windows at once
- **% used ↔ % left toggle** — flip the entire display; preference is GSettings-persisted across restarts
- **Desktop notifications** — fires when any window drops below 20%, deduplicated per reset window
- **Manual refresh** — trigger an immediate poll from the popup menu
- **Exponential backoff** — backs off gracefully on network errors or API rate limits

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

Open the popup → **Configure** to choose what the tray label shows:

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

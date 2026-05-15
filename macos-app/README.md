# Claude Monitor — macOS app

Native macOS menu bar app for Claude Monitor. Lightweight (~2 MB, no runtime), no third-party host app required.

## Requirements

- macOS 13 (Ventura) or newer
- Xcode Command Line Tools — install with `xcode-select --install` if you don't have them

## Build

```bash
bash build.sh
```

This compiles a universal binary (arm64 + x86_64) and assembles `Claude Monitor.app` in this folder.

## Install

```bash
mv "Claude Monitor.app" /Applications/
open "/Applications/Claude Monitor.app"
```

**First launch only:** macOS will refuse to open the app because it isn't signed by an Apple Developer. Bypass:

- **Right-click** the app in Finder → **Open** → **Open** in the confirmation dialog.
- macOS remembers your choice for future launches.

The menu bar entry will appear in the top-right with two percentages — one per provider. Click it for session/weekly breakdowns and reset timers.

## Credentials

Reads the same files as the Linux extension and the xbar plugin — no extra setup if you already use Claude Code or Codex CLI:

| Provider | File |
|----------|------|
| Claude | `~/.claude/.credentials.json` |
| Codex  | `~/.codex/auth.json` |

If a credentials file is missing, that provider's section in the dropdown shows `⚠ credentials not found` and the menu bar shows `?` for it.

## Color thresholds

Match the Linux extension and the xbar plugin:

| Remaining | Color |
|-----------|-------|
| ≥ 80% | Green |
| 50 – 79% | Emerald |
| 30 – 49% | Yellow |
| 15 – 29% | Orange |
| < 15% | Red |

## Polling

Every 180 seconds, plus immediate refresh on **Refresh now** from the dropdown.

# Claude Monitor — macOS (xbar plugin)

Lightweight macOS menu bar plugin for Claude Monitor. Uses [xbar](https://xbarapp.com) — no Electron, no app bundle, just a Node.js script.

## Requirements

- macOS 12+
- [xbar](https://xbarapp.com) — free, open source
- Node.js 16+ (`brew install node`)

## Install

1. Install xbar from [xbarapp.com](https://xbarapp.com)

2. Open xbar → **Open Plugin Folder**

3. Copy the plugin file there:
   ```bash
   cp claude-monitor.5m.js "$(xbar plugin-dir 2>/dev/null || echo ~/Library/Application\ Support/xbar/plugins)"
   chmod +x ~/Library/Application\ Support/xbar/plugins/claude-monitor.5m.js
   ```

4. Click **Refresh All** in xbar

## What it looks like

```
Menu bar:   ✦ 24%  ⬡ 59%

Dropdown:
  ✦ Claude
     Session   76% used   resets in 3h 30m
     Weekly    16% used   resets in 6d 6h
  ──────────────────────────────
  ⬡ Codex
     Session    1% used   resets in 4h 59m
     Weekly    41% used   resets in 4d 2h
  ──────────────────────────────
  ↺ Refresh
  GitHub
  Cybrosys Assista
```

Colors match the Linux extension:

| Remaining | Color |
|-----------|-------|
| ≥ 80% | 🟢 Green |
| 50 – 79% | 🟩 Emerald |
| 30 – 49% | 🟡 Yellow |
| 15 – 29% | 🟠 Orange |
| < 15% | 🔴 Red |

## Credentials

Reads the same credential files as the Linux extension — no extra setup if you use Claude Code or Codex CLI:

| Provider | File |
|----------|------|
| Claude | `~/.claude/.credentials.json` |
| Codex | `~/.codex/auth.json` |

## Refresh interval

The filename `claude-monitor.5m.js` tells xbar to refresh every **5 minutes**. Rename to change interval:
- `claude-monitor.1m.js` → every 1 minute
- `claude-monitor.3m.js` → every 3 minutes
- `claude-monitor.10m.js` → every 10 minutes

# claudemonitor@assista

GNOME Shell extension source. Targets GNOME 45–49.

## Structure

```
extension.js          — entry point, GObject UI, dependency wiring
metadata.json         — UUID, name, supported shell versions, settings-schema
stylesheet.css        — popup and tray styles
icons/                — claude.svg, codex.svg
schemas/              — GSettings schema XML
lib/core/             — scheduler, state, backoff, notifications, aggregate, normalize
lib/providers/        — claude.js, codex.js (OAuth + usage fetch)
lib/runtime/          — fetch.js (Soup 3.0), fs.js (Gio)
lib/ui/               — render.js (pure view-model builder)
```

## Local development

Run from repository root:

```bash
npx bun test                    # unit tests
bash scripts/dev/pack.sh        # produces claudemonitor@assista.shell-extension.zip
bash scripts/dev/install.sh     # installs/updates in ~/.local/share/gnome-shell/extensions/
bash scripts/dev/enable.sh      # gnome-extensions enable claudemonitor@assista
bash scripts/dev/disable.sh     # gnome-extensions disable claudemonitor@assista
```

Re-login (Wayland) or `Alt+F2 → r` (X11) after install to reload GNOME Shell.

## Logs

```bash
journalctl --user -f /usr/bin/gnome-shell | grep -E 'claudemonitor|JS ERROR'
```

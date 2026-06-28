# My Caelestia fork

A personal fork of [`caelestia-dots/shell`](https://github.com/caelestia-dots/shell)
with my own fixes and features baked in, plus my user-space config in
[`personal/`](.).

## What's changed vs upstream

### Shell code (the reason this is a fork — these get wiped by package updates otherwise)

- **Bluetooth volume fix** (`services/Audio.qml`) — volume/mute are driven via
  `wpctl` (which writes the PipeWire device *route*) instead of node-level
  writes, which don't propagate to route-owned sinks like Bluetooth speakers.
  Works for ALSA and bluez alike.
- **Display / Monitor settings page** (`modules/nexus/pages/DisplayPage.qml`,
  `modules/nexus/pages/display/MonitorSection.qml`, registered in
  `modules/nexus/PageRegistry.qml` + `PageCompRegistry.qml`) — a new page in the
  Nexus settings app to set resolution / refresh rate / scale / position, pick
  which output is on, and enable/disable monitors. Reads `hyprctl monitors all`,
  applies live via `hyprctl`, and persists to `~/.config/hypr/monitors.d/`.

### User-space config (in `personal/`)

- **Wallpaper Engine** support in the wallpaper picker (`we-sync.sh`,
  `wallpaper-posthook.sh`, wired via `cli.json`).
- **shell.json** — launcher action prefix `.`, bar/appearance tweaks, pinned
  wallpaper dir.
- **German keyboard layout** (`hypr/hyprland/input.lua`).
- Saved **monitor configs** (`hypr/monitors.d/`, machine-specific).

## How it works

`quickshell` loads `~/.config/quickshell/caelestia` in preference to the system
package at `/etc/xdg/quickshell/caelestia`. So this repo, cloned to that path,
*is* the running shell — and the `caelestia-shell` package can update without
ever overwriting these changes.

## Install on a new machine

```sh
# 1. Install caelestia normally (dotfiles + shell package).
# 2. Run the shell from this fork:
git clone https://github.com/0Inexis0/shell.git ~/.config/quickshell/caelestia
# 3. Link the user-space config into place:
~/.config/quickshell/caelestia/personal/install.sh
# 4. Restart the shell:
qs -c caelestia kill; caelestia shell -d
```

## Update from upstream (without losing my changes)

```sh
cd ~/.config/quickshell/caelestia
git fetch upstream
git merge upstream/main      # or a release tag, e.g. v2.1.0
# resolve any conflicts (rare — my new files don't overlap upstream)
qs -c caelestia kill; caelestia shell -d
```

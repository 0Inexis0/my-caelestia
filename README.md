<h1 align=center>my-caelestia</h1>

<div align=center>

My personal fork of the [Caelestia](https://github.com/caelestia-dots) desktop shell —
the [`caelestia-dots/shell`](https://github.com/caelestia-dots/shell) rice with my own
fixes and features baked in, so I can reinstall my exact setup anywhere and still pull
upstream updates without losing my changes.

![last commit](https://img.shields.io/github/last-commit/0Inexis0/my-caelestia?style=for-the-badge&labelColor=101418&color=9ccbfb)
![based on caelestia](https://img.shields.io/badge/based%20on-caelestia--dots%2Fshell-b9c8da?style=for-the-badge&labelColor=101418)

</div>

## What I changed vs upstream

### Shell code

- **🔧 Bluetooth volume fix** (`services/Audio.qml`) — the bar's volume slider, scroll and
  mute did nothing on Bluetooth speakers. Bluetooth volume lives on the PipeWire device
  *route*, which the node-level setter never touches, so it's now driven via `wpctl`
  instead. Works for both analog (ALSA) and Bluetooth (bluez) outputs.
- **🖥️ Display / Monitor settings page** (`modules/nexus/pages/DisplayPage.qml`,
  `modules/nexus/pages/display/MonitorSection.qml`) — a brand-new page in the Nexus
  settings app to pick resolution, refresh rate, scale and position per monitor, choose
  which output is on, and enable/disable displays. Reads `hyprctl monitors`, applies live
  via `hyprctl`, and persists to `~/.config/hypr/monitors.d/`.

### User-space config — see [`personal/`](personal/)

- **🎮 Wallpaper Engine** support in the wallpaper picker (`we-sync.sh` + `wallpaper-posthook.sh`).
- **⌨️ German keyboard layout** and launcher tweaks (`.` action prefix), bar/appearance tweaks.

## How this fork works

`quickshell` loads `~/.config/quickshell/caelestia` in preference to the system package at
`/etc/xdg/quickshell/caelestia`. So this repo, cloned to that path, **is** the running shell —
which means the `caelestia-shell` package can update freely without ever overwriting my changes.

## Install on a new machine

```sh
# 1. Install caelestia normally first (dotfiles + shell package):
#    https://github.com/caelestia-dots/caelestia
# 2. Run the shell from this fork:
git clone https://github.com/0Inexis0/my-caelestia.git ~/.config/quickshell/caelestia
# 3. Link my user-space config into place:
~/.config/quickshell/caelestia/personal/install.sh
# 4. Restart the shell:
qs -c caelestia kill; caelestia shell -d
```

## Update from upstream (keeping my changes)

```sh
cd ~/.config/quickshell/caelestia
git fetch upstream
git merge upstream/main          # or a release tag, e.g. v2.1.0
qs -c caelestia kill; caelestia shell -d
```

My commits stay on top; merges are clean because my new files don't overlap upstream's.

## Credits

All the real work is [Caelestia](https://github.com/caelestia-dots) by
[@soramane](https://ko-fi.com/soramane) and contributors — this is just my personal layer
on top. For full shell documentation (configuration, all options, FAQ), see the
[upstream README](https://github.com/caelestia-dots/shell). For the complete dotfiles, see
the [main caelestia repo](https://github.com/caelestia-dots/caelestia).

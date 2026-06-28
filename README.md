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
  via `hyprctl`, and persists to `~/.config/hypr/monitors.d/` (restored on login by
  `execs.lua` below).

### User-space config — see [`personal/`](personal/)

- **🎮 Wallpaper Engine** support in the wallpaper picker (`we-sync.sh` + `wallpaper-posthook.sh`).
- **⌨️ Hyprland tweaks** — German keyboard layout (`input.lua`), my custom keybinds
  (`keybinds.lua`, incl. `Super+A` for the AI page), and monitor restore + automatic
  internal-display disable when an external is plugged in (`execs.lua`, the companion to
  the Display page above).
- **🎨 Shell config** — `shell.json` / `cli.json`: launcher `.` action prefix, bar and
  appearance tweaks.

`personal/install.sh` symlinks all of this into `~/.config` so the repo stays the single
source of truth. The machine-specific monitor configs only link for outputs actually
present on the current machine, so the same repo installs cleanly on any hardware.

## How this fork works

`quickshell` loads `~/.config/quickshell/caelestia` in preference to the system package at
`/etc/xdg/quickshell/caelestia`. So this repo, cloned to that path, **is** the running shell —
which means the `caelestia-shell` package can update freely without ever overwriting my changes.

## Install on a new machine — one command

On a fresh Arch/CachyOS machine, paste this in a normal terminal (it asks for your sudo
password once):

```sh
curl -fsSL https://raw.githubusercontent.com/0Inexis0/my-caelestia/mine/personal/bootstrap.sh -o /tmp/rice.sh && bash /tmp/rice.sh
```

It installs Caelestia itself (packages, Hyprland, fonts), the extras my rice uses (SDDM
login theme + Wallpaper Engine renderer), this fork, my config, and the `rice-update`
command — then starts the shell. Done.

## Update — one command

```sh
rice-update
```

That's the whole update. It runs a full system update (`yay -Syu`, so Caelestia and
quickshell move together), auto-saves my changes, rebases them onto the new version,
**test-loads it before switching**, restarts — and if anything ever goes wrong it rolls
back, falling back to the plain system shell so the desktop is never left dead.

Just want to sync the shell without a system update? `rice-update --skip-system`.

## Credits

All the real work is [Caelestia](https://github.com/caelestia-dots) by
[@soramane](https://ko-fi.com/soramane) and contributors — this is just my personal layer
on top. For full shell documentation (configuration, all options, FAQ), see the
[upstream README](https://github.com/caelestia-dots/shell). For the complete dotfiles, see
the [main caelestia repo](https://github.com/caelestia-dots/caelestia).

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

### Shell code (the QML shell itself)

- **🤖 AI assistant page** (`modules/ai/`, `services/Ollama.qml`) — a built-in chat panel
  backed by a local [Ollama](https://ollama.com) server. Toggle it with **`Super+A`**. It
  lists your installed models, streams responses (including the model's "thinking" stream),
  keeps a persistent multi-chat history, supports image attachments for vision models, and
  exposes context-length presets and a temperature control. Talks to `$OLLAMA_HOST` (default
  `http://127.0.0.1:11434`) over `curl` — so it needs Ollama installed and running, but no
  cloud/API key. Wired into the drawer/panel system (`modules/drawers/`, `Shortcuts.qml`,
  Nexus page registries).
- **🔧 Bluetooth volume fix** (`services/Audio.qml`) — the bar's volume slider, scroll and
  mute did nothing on Bluetooth speakers. Bluetooth volume lives on the PipeWire device
  *route*, which the node-level setter never touches, so it's now driven via `wpctl`
  instead. Works for both analog (ALSA) and Bluetooth (bluez) outputs.
- **🖥️ Display / Monitor settings page** (`modules/nexus/pages/DisplayPage.qml`,
  `modules/nexus/pages/display/MonitorSection.qml`) — a new page in the Nexus settings app
  to pick resolution, refresh rate and scale per monitor, enable/disable outputs, and
  auto-disable the internal panel when an external is connected. Reads `hyprctl monitors`,
  applies live via the Lua API, and persists to `~/.config/hypr/monitors.d/` (restored on
  login by `execs.lua`). Toggling "Auto-disable" off now also re-enables the screen
  (previously it left the display off and looked like it did nothing).

### User-space config — see [`personal/`](personal/)

- **🎮 Wallpaper Engine** integration in the wallpaper picker (`we-sync.sh`,
  `wallpaper-posthook.sh`, `we-restore.sh`). Picking a Wallpaper Engine wallpaper runs
  `linux-wallpaperengine` over the static background; picking a normal image stops it.
  `we-restore.sh` re-launches it **at login** and **when a monitor is added/removed** (the
  post-hook only fires on a wallpaper *change*), so a WE wallpaper survives reboots and
  extends onto a newly-enabled screen automatically.
- **⌨️ Hyprland config** (Lua, not `.conf`) — German keyboard layout (`input.lua`), my
  keybinds (`keybinds.lua`, incl. `Super+A` for the AI page), touchpad gestures
  (`gestures.lua`, 4-finger-down = sleep), window rules (`rules.lua`: Bitwarden + PiP
  floats, special workspaces), and startup + monitor management (`execs.lua`: gammastep
  night light, the auto-disable companion to the Display page, and the WE restore hook).
- **😴 Sleep = plain suspend, not hibernate** — this machine has zram-only swap (no disk
  swap / `resume=`), so hibernation is impossible and any attempt wedged the session. The
  idle action (`shell.json`, 10 min), the sleep gesture and the `Super+Shift+L` keybind all
  use `systemctl suspend`. Idle chain: lock @3 min → screen off @5 min → suspend @10 min.
- **🎨 Shell config** (`shell.json`, `cli.json`) — launcher `.` action prefix, bar/appearance
  tweaks, wallpaper directory pinned to `~/Bilder/Wallpapers`, and the idle/suspend timeouts
  above.

## What's in [`personal/`](personal/)

| Path | What it is |
|---|---|
| `bootstrap.sh` | One-command fresh-machine installer (packages → fork → config). |
| `install.sh` | Symlinks `personal/config/` into `~/.config` and installs the `rice-update` command. |
| `update.sh` | The `rice-update` command — system update + rebase onto upstream + safe test-load/rollback. |
| `config/caelestia/shell.json`, `cli.json` | Shell (QML) and CLI config: bar, idle/suspend, wallpaper dir, post-hook. |
| `config/caelestia/we-sync.sh`, `wallpaper-posthook.sh`, `we-restore.sh` | Wallpaper Engine integration (sync previews, switch on selection, restore on login/monitor change). |
| `config/hypr/hyprland.lua` + `hypr/hyprland/*.lua` | Full Hyprland Lua config (entry point + all modules). |
| `config/hypr/variables.lua` | App/keybind/visual variables (incl. `sleepGestureCmd`). |
| `config/hypr/scripts/restart-shell.sh` | Debounced shell restart + WE restore on monitor add/remove. |
| `config/hypr/monitors.d/*.conf` | Per-machine saved monitor modes — only linked for outputs actually present. |

`install.sh` symlinks all of this into `~/.config` so the repo stays the single source of
truth. Not tracked on purpose: `hypr/scheme/` (auto-generated theming) and the empty
`hypr-user.lua` / `hypr-vars.lua` / `user-config.fish` stubs (auto-created on first run).

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

> The AI page additionally needs [Ollama](https://ollama.com) running locally
> (`ollama serve` + at least one pulled model). Everything else works without it.

## Update — one command

```sh
rice-update
```

That's the whole update. It runs a full system update (`yay -Syu`, so Caelestia and
quickshell move together), auto-saves my changes, rebases them onto the new version,
**test-loads it before switching**, restarts — and if anything ever goes wrong it rolls
back, falling back to the plain system shell so the desktop is never left dead.

Just want to sync the shell without a system update? `rice-update --skip-system`.

> Note: `rice-update` only syncs the **shell repo**. The `personal/config` files are
> deployed by `install.sh` (run once by `bootstrap.sh`); edit a live file and mirror the
> change back into `personal/config/` so it stays tracked.

## Credits

All the real work is [Caelestia](https://github.com/caelestia-dots) by
[@soramane](https://ko-fi.com/soramane) and contributors — this is just my personal layer
on top. For full shell documentation (configuration, all options, FAQ), see the
[upstream README](https://github.com/caelestia-dots/shell). For the complete dotfiles, see
the [main caelestia repo](https://github.com/caelestia-dots/caelestia).

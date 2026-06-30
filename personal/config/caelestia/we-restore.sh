#!/usr/bin/env bash
# we-restore.sh — re-launch Wallpaper Engine at login.
#
# Caelestia's wallpaper.postHook only runs when the wallpaper *changes*, so after
# a reboot a Wallpaper Engine wallpaper is never re-rendered until you reselect
# it in the picker. Caelestia records the active wallpaper in path.txt; we read
# it back and feed it through the same posthook, which (re)launches
# linux-wallpaperengine for WE wallpapers and is a no-op for normal images.
set -uo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/wallpaper/path.txt"
POSTHOOK="$HOME/.config/caelestia/wallpaper-posthook.sh"

[[ -r "$STATE" && -x "$POSTHOOK" ]] || exit 0
path="$(cat "$STATE" 2>/dev/null)"
[[ -n "$path" ]] || exit 0

# Only WE wallpapers need restoring; bail early for plain images so we never
# touch a running renderer needlessly.
[[ "$path" == *"/WallpaperEngine/"* ]] || exit 0

# Wait for Hyprland's outputs (the posthook auto-detects them via hyprctl) and
# for the caelestia shell's static background layer that lwe renders over.
for _ in $(seq 1 40); do
    hyprctl monitors -j >/dev/null 2>&1 && break
    sleep 0.5
done
sleep 2   # give the shell's background layer a moment to come up

WALLPAPER_PATH="$path" exec "$POSTHOOK"

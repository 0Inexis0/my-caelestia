#!/usr/bin/env bash
# Reinstall my personal Caelestia customizations on a new machine.
#
# The SHELL itself (Bluetooth volume fix, Display/Monitor settings page, etc.)
# lives in this repo and runs simply by having this repo cloned to:
#     ~/.config/quickshell/caelestia
# quickshell loads that path in preference to the system package in /etc/xdg,
# so the package can update freely without ever touching these changes.
#
# This script handles the *other* half: the user-space config files
# (Wallpaper Engine scripts, shell.json tweaks, German keyboard layout, ...).
# It symlinks them out of this repo into ~/.config so the repo stays the single
# source of truth — edit a file once, it's tracked here automatically.

set -euo pipefail

SRC="$(cd "$(dirname "$0")/config" && pwd)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}"

link() {
    local from="$1" to="$2"
    mkdir -p "$(dirname "$to")"
    if [ -e "$to" ] && [ ! -L "$to" ]; then
        mv "$to" "$to.pre-mine.bak"
        echo "  backed up existing $to -> $(basename "$to").pre-mine.bak"
    fi
    ln -sfn "$from" "$to"
    echo "  linked $to"
}

echo "Linking Caelestia config + Wallpaper Engine scripts..."
chmod +x "$SRC"/caelestia/*.sh
link "$SRC/caelestia/shell.json"            "$DEST/caelestia/shell.json"
link "$SRC/caelestia/cli.json"              "$DEST/caelestia/cli.json"
link "$SRC/caelestia/we-sync.sh"            "$DEST/caelestia/we-sync.sh"
link "$SRC/caelestia/wallpaper-posthook.sh" "$DEST/caelestia/wallpaper-posthook.sh"

echo "Linking Hypr tweaks (German keyboard layout)..."
link "$SRC/hypr/hyprland/input.lua" "$DEST/hypr/hyprland/input.lua"

echo "Linking persisted monitor configs (machine-specific — skip/edit on other hardware)..."
for f in "$SRC"/hypr/monitors.d/*.conf; do
    [ -e "$f" ] || continue
    link "$f" "$DEST/hypr/monitors.d/$(basename "$f")"
done

echo
echo "Done. Restart the shell to apply:"
echo "    qs -c caelestia kill; caelestia shell -d"

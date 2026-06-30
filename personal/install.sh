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

PERSONAL="$(cd "$(dirname "$0")" && pwd)"
SRC="$PERSONAL/config"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$HOME/.local/bin"

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
link "$SRC/caelestia/we-restore.sh"         "$DEST/caelestia/we-restore.sh"

echo "Linking Hypr tweaks (keybinds, monitor restore/auto-disable, German keyboard)..."
link "$SRC/hypr/hyprland/input.lua"     "$DEST/hypr/hyprland/input.lua"
link "$SRC/hypr/hyprland/keybinds.lua"  "$DEST/hypr/hyprland/keybinds.lua"
link "$SRC/hypr/hyprland/execs.lua"     "$DEST/hypr/hyprland/execs.lua"
link "$SRC/hypr/hyprland/variables.lua" "$DEST/hypr/hyprland/variables.lua"
link "$SRC/hypr/scripts/restart-shell.sh" "$DEST/hypr/scripts/restart-shell.sh"

echo "Linking persisted monitor configs (only for monitors on THIS machine)..."
# These .conf files are machine-specific (resolution/refresh/scale for a given
# output). Linking another machine's config can force an unsupported mode and
# black out a display, so only link a config whose output is actually present.
# On a fresh TTY install Hyprland isn't running yet — skip them entirely; the
# Display settings page recreates them per-machine on first use.
if command -v hyprctl >/dev/null 2>&1 && present="$(hyprctl monitors all 2>/dev/null | grep -oP '^Monitor \K[^ ]+')" && [ -n "$present" ]; then
    for f in "$SRC"/hypr/monitors.d/*.conf; do
        [ -e "$f" ] || continue
        name="$(basename "$f" .conf)"
        if printf '%s\n' "$present" | grep -qxF "$name"; then
            link "$f" "$DEST/hypr/monitors.d/$name.conf"
        else
            echo "  skipped $name.conf (no monitor named '$name' on this machine)"
        fi
    done
else
    echo "  (Hyprland not running yet — skipping; the Display settings page will create these per-machine)"
fi

echo "Installing the 'rice-update' command..."
mkdir -p "$BIN"
ln -sfn "$PERSONAL/update.sh" "$BIN/rice-update"
chmod +x "$PERSONAL/update.sh" "$PERSONAL/bootstrap.sh"
echo "  linked $BIN/rice-update  ->  update anytime by typing: rice-update"

echo
echo "Done. Restart the shell to apply:"
echo "    qs -c caelestia kill; caelestia shell -d"

#!/usr/bin/env bash
# Run after games are closed. Install just the monitor changes for this desktop.
set -eu
src=$(dirname "$(dirname "$(realpath "$0")")")
shell_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"
hypr_dir="$HOME/.config/hypr"
backup=$(mktemp -d "$hypr_dir/display-backup.XXXXXX")
printf 'Backup: %s\n' "$backup"
for file in assets/displayctl.py utils/Display.js modules/nexus/pages/DisplayPage.qml modules/nexus/pages/display/{MonitorSection,DisplayModeRow}.qml; do
    if [[ -f "$shell_dir/$file" ]]; then
        cp "$shell_dir/$file" "$backup/"
    fi
    install -m644 "$src/$file" "$shell_dir/$file"
done
file=hyprland/execs.lua
cp "$hypr_dir/$file" "$backup/"
if ! [[ "$src/personal/config/hypr/$file" -ef "$hypr_dir/$file" ]]; then
    ln -sfn "$src/personal/config/hypr/$file" "$hypr_dir/$file"
fi
bash "$src/personal/install-login-monitor.sh"

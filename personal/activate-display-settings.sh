#!/usr/bin/env bash
# Run after games are closed. Install just the monitor changes for this desktop.
set -eu
src=$(dirname "$(dirname "$(realpath "$0")")")
shell_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"
hypr_dir="$HOME/.config/hypr"
backup=$(mktemp -d "$hypr_dir/display-backup.XXXXXX")
printf 'Backup: %s\n' "$backup"
for file in assets/displayctl.py modules/nexus/pages/DisplayPage.qml modules/nexus/pages/display/MonitorSection.qml; do
    cp "$shell_dir/$file" "$backup/"
    install -m644 "$src/$file" "$shell_dir/$file"
done
file=hyprland/execs.lua
cp "$hypr_dir/$file" "$backup/"
if ! [[ "$src/personal/config/hypr/$file" -ef "$hypr_dir/$file" ]]; then
    install -m644 "$src/personal/config/hypr/$file" "$hypr_dir/$file"
fi
bash "$src/personal/install-login-monitor.sh"

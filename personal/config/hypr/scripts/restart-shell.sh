#!/bin/bash
# Debounced caelestia shell restart, triggered on monitor add/remove so the bar
# and panels reliably re-draw on the current set of monitors. If several monitor
# events fire in quick succession, only the last invocation actually restarts.
STAMP="${XDG_RUNTIME_DIR:-/tmp}/caelestia-restart-stamp"
NOW="$(date +%s%N)"
echo "$NOW" > "$STAMP"

# Wait for the monitor layout to settle; bail if a newer event superseded us.
sleep 1.5
[ "$(cat "$STAMP" 2>/dev/null)" = "$NOW" ] || exit 0

caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null
sleep 0.5
caelestia shell -d

# Re-extend the Wallpaper Engine wallpaper onto the current set of outputs. The
# wallpaper.postHook only fires when the wallpaper *changes*, not when a monitor
# is added/removed, so without this an enabled second screen shows no live
# wallpaper until reselected. we-restore reads the active wallpaper and relaunches
# linux-wallpaperengine across all current outputs (no-op for normal images).
bash ~/.config/caelestia/we-restore.sh

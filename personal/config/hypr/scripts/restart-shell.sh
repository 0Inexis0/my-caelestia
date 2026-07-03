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

# Wait until the old instance is really gone before starting the new one. With
# a fixed 0.5s sleep, `caelestia shell -d` can race the dying instance's
# leftover lock/socket, conclude a shell is already running, and start nothing
# (this left the session without a shell after boot-time monitor events).
for _ in $(seq 1 20); do
    pgrep -f "qs -c caelestia" >/dev/null || break
    sleep 0.25
done
pkill -9 -f "qs -c caelestia" 2>/dev/null
sleep 0.2
caelestia shell -d

# Verify it actually came up; one retry covers a lost start race.
sleep 2
pgrep -f "qs -c caelestia" >/dev/null || caelestia shell -d

# Re-extend the Wallpaper Engine wallpaper onto the current set of outputs. The
# wallpaper.postHook only fires when the wallpaper *changes*, not when a monitor
# is added/removed, so without this an enabled second screen shows no live
# wallpaper until reselected. we-restore reads the active wallpaper and relaunches
# linux-wallpaperengine across all current outputs (no-op for normal images).
bash ~/.config/caelestia/we-restore.sh

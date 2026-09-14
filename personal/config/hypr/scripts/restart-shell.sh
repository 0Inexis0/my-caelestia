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

# Select by configuration, including managed releases launched with qs -p.
qs -c caelestia kill 2>/dev/null || true
for _ in $(seq 1 40); do
    qs -c caelestia ipc show >/dev/null 2>&1 || break
    sleep 0.2
done
if qs -c caelestia ipc show >/dev/null 2>&1; then
    echo "Previous shell has not exited; skipping duplicate launch" >&2
    exit 1
fi
caelestia shell -d

# Re-extend the Wallpaper Engine wallpaper onto the current set of outputs. The
# wallpaper.postHook only fires when the wallpaper *changes*, not when a monitor
# is added/removed, so without this an enabled second screen shows no live
# wallpaper until reselected. we-restore reads the active wallpaper and relaunches
# linux-wallpaperengine across all current outputs (no-op for normal images).
bash ~/.config/caelestia/we-restore.sh

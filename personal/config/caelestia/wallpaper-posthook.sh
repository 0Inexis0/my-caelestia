#!/usr/bin/env bash
# wallpaper-posthook.sh — Caelestia wallpaper.postHook
#
# Caelestia runs this every time the wallpaper changes, with $WALLPAPER_PATH set.
# If the chosen wallpaper is a Wallpaper Engine preview (lives under the
# WallpaperEngine/ subfolder, with the workshop id encoded as "... [<id>].ext"),
# we hand it off to linux-wallpaperengine, which renders over Caelestia's static
# background layer. For any normal image we just kill the renderer so the static
# wallpaper shows through again.
set -uo pipefail

MONITORS=(eDP-1)          # Hyprland output(s) to render on
EXTRA_OPTS=(--silent)     # video wallpapers play muted

# The kernel truncates the process name to 15 chars ("linux-wallpaper"), so we
# match that exact (truncated) comm rather than the full name or cmdline. Using
# -x avoids killing the Proton "wallpaper64.exe" app or anything else.
stop_we() { pkill -x linux-wallpaper 2>/dev/null || true; }

path="${WALLPAPER_PATH:-}"

# Only WE previews trigger the renderer.
if [[ "$path" != *"/WallpaperEngine/"* ]]; then
    stop_we
    exit 0
fi

# Pull the workshop id out of "Title [123456789].jpg"
id="$(printf '%s' "$path" | grep -oE '\[[0-9]+\]' | tail -1 | tr -d '[]')"
if [[ -z "$id" ]]; then
    stop_we
    exit 0
fi

stop_we
sleep 0.2

args=("${EXTRA_OPTS[@]}")
for m in "${MONITORS[@]}"; do
    args+=(--screen-root "$m" --bg "$id")
done

# Detach so the hook returns immediately; log for debugging.
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/wallpaper/we.log"
mkdir -p "$(dirname "$LOG")"
setsid -f linux-wallpaperengine "${args[@]}" >"$LOG" 2>&1 || \
    echo "failed to launch linux-wallpaperengine" >>"$LOG"

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

# Detect the active Hyprland output(s) at runtime. Connector names can change
# across kernel/driver updates (e.g. eDP-1 -> eDP-2), which would otherwise make
# linux-wallpaperengine bail with "No outputs could be initialized".
mapfile -t MONITORS < <(hyprctl monitors -j 2>/dev/null \
    | python3 -c 'import json,sys; print("\n".join(m["name"] for m in json.load(sys.stdin)))' 2>/dev/null)
[[ ${#MONITORS[@]} -gt 0 ]] || MONITORS=(eDP-1)   # fall back if detection fails
EXTRA_OPTS=(--silent --fps 60)   # muted; cap at 60fps
SCALING=stretch                  # stretch to the whole output: no borders and
                                 # no cropping (distorts mismatched aspects)

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
    # --scaling is per-output, so it must follow this output's --bg.
    args+=(--screen-root "$m" --bg "$id" --scaling "$SCALING")
done

# Detach so the hook returns immediately; log for debugging.
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/wallpaper/we.log"
mkdir -p "$(dirname "$LOG")"
setsid -f linux-wallpaperengine "${args[@]}" >"$LOG" 2>&1

# setsid forks, so the launch above reports success even when the renderer dies
# on the spot -- which is exactly what an Arch soname bump does to it (e.g.
# ffmpeg 8 -> 9 renamed libavcodec.so.62 -> .63, leaving the prebuilt binary
# unable to start). That failed silently and just looked like "the live
# wallpaper stopped working", so check it actually survived and say why if not.
# Detached as well, so the hook itself still returns immediately.
LOG="$LOG" setsid -f bash -c '
    sleep 1.5
    pgrep -x linux-wallpaper >/dev/null && exit 0
    reason="$(tail -n 3 "$LOG" | tr "\n" " ")"
    echo "renderer exited immediately after launch" >>"$LOG"
    notify-send -a "Wallpaper Engine" -u critical \
        "Live wallpaper failed to start" "${reason:-see $LOG}"
' 2>/dev/null

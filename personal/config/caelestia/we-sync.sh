#!/usr/bin/env bash
# we-sync.sh — surface Wallpaper Engine wallpapers in Caelestia's picker.
#
# For every downloaded WE wallpaper it:
#   1. symlinks the wallpaper folder into the Steam "content/431960" dir so that
#      `linux-wallpaperengine <id>` can resolve it by id, and
#   2. drops a symlink to its preview image into ~/Bilder/Wallpapers/WallpaperEngine
#      so it shows up (with thumbnail + colour generation) in the launcher.
#
# Re-run this whenever you subscribe to / download new WE wallpapers.
set -euo pipefail

WALLS_DIR="${XDG_PICTURES_DIR:-$HOME/Bilder}/Wallpapers"
WE_PICKER_DIR="$WALLS_DIR/WallpaperEngine"

STEAM_ROOTS=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
)
WORKSHOP_REL=("steamapps/workshop/downloads/431960" "steamapps/workshop/content/431960")

# Canonical content dir linux-wallpaperengine resolves ids from.
CONTENT_DIR=""
for root in "${STEAM_ROOTS[@]}"; do
    if [[ -d "$root/steamapps" ]]; then
        CONTENT_DIR="$root/steamapps/workshop/content/431960"
        break
    fi
done
[[ -n "$CONTENT_DIR" ]] || { echo "No Steam install found" >&2; exit 1; }
mkdir -p "$CONTENT_DIR" "$WE_PICKER_DIR"

sanitize() {
    # strip slashes/newlines, collapse whitespace, trim
    printf '%s' "$1" | tr '/\n\r' '   ' | tr -s ' ' | sed 's/^ *//;s/ *$//'
}

declare -A seen_ids=()
count=0

while IFS= read -r -d '' proj; do
    src_dir="$(dirname "$proj")"
    id="$(basename "$src_dir")"
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    [[ -n "${seen_ids[$id]:-}" ]] && continue   # prefer first hit (downloads before content)
    seen_ids[$id]=1

    # preview and title on separate lines: titles often contain spaces, so a
    # single-line "title preview" would make `read title preview` mis-split and
    # drop the real preview filename. Preview first so it's resolved correctly
    # even if the title is unusual.
    { read -r preview; read -r title; } < <(python3 - "$proj" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit()
print(d.get("preview") or "preview.jpg")
print(d.get("title") or "Untitled")
PY
)
    preview_path="$src_dir/$preview"
    [[ -f "$preview_path" ]] || continue
    ext="${preview##*.}"

    # 1. expose folder under content/431960 for id-based resolution
    if [[ "$src_dir" != "$CONTENT_DIR/$id" && ! -e "$CONTENT_DIR/$id" ]]; then
        ln -sfn "$src_dir" "$CONTENT_DIR/$id"
    fi

    # 2. copy preview into the picker dir, encoding the id in the filename.
    #    Copy (not symlink) because Caelestia's FileSystemModel does not follow
    #    symlinked files, so they never show up in the launcher.
    name="$(sanitize "$title") [$id].$ext"
    dest="$WE_PICKER_DIR/$name"
    [[ -f "$dest" ]] || cp -f "$preview_path" "$dest"
    count=$((count + 1))
done < <(
    for root in "${STEAM_ROOTS[@]}"; do
        for rel in "${WORKSHOP_REL[@]}"; do
            [[ -d "$root/$rel" ]] && find "$root/$rel" -mindepth 2 -maxdepth 2 -name project.json -print0
        done
    done
)

# Prune picker entries whose wallpaper is no longer present (removed/unsubscribed)
shopt -s nullglob
for f in "$WE_PICKER_DIR"/*; do
    fid="$(printf '%s' "$f" | grep -oE '\[[0-9]+\]' | tail -1 | tr -d '[]')"
    [[ -n "$fid" && -z "${seen_ids[$fid]:-}" ]] && rm -f "$f"
done
# Prune broken folder symlinks in the content dir
for link in "$CONTENT_DIR"/*; do
    [[ -L "$link" && ! -e "$link" ]] && rm -f "$link"
done

echo "Synced $count Wallpaper Engine wallpaper(s) -> $WE_PICKER_DIR"

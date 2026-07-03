#!/usr/bin/env bash
#
# FULL one-command install of my rice on a fresh Arch/CachyOS machine.
# Installs Caelestia itself (only if missing), the extras my setup uses (you pick
# which), then layers my fork + config on top. Safe to re-run — anything already
# present is detected and skipped (never installed twice).
#
#   curl -fsSL https://raw.githubusercontent.com/0Inexis0/my-caelestia/mine/personal/bootstrap.sh -o /tmp/rice.sh && bash /tmp/rice.sh
#
# (Run it from a normal terminal/TTY as your user — NOT as root. It asks for your
#  sudo password once. Piping straight into bash works too, but then it can't ask
#  questions, so it just installs everything with default settings.)
#
set -uo pipefail

REPO="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
URL="https://github.com/0Inexis0/my-caelestia.git"
UPSTREAM="https://github.com/caelestia-dots/shell.git"

c_info() { printf '\n\033[1;36m%s\033[0m\n' "$*"; }
c_ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m%s\033[0m\n' "$*"; }
c_step() { printf '\033[1;35m▸ %s\033[0m\n' "$*"; }

# We can only ask questions if there's a real terminal on stdin. When piped
# (curl | bash) there isn't, so we silently take every default instead.
INTERACTIVE=0; [ -t 0 ] && INTERACTIVE=1

# Yes/No prompt. $2 = default ("y" or "n"). Returns 0 for yes.
ask() {
    local q="$1" def="${2:-y}" ans hint="[Y/n]"
    [ "$def" = n ] && hint="[y/N]"
    [ "$INTERACTIVE" = 0 ] && { [ "$def" = y ]; return; }
    read -rp "$(printf '\033[1;36m? %s %s \033[0m' "$q" "$hint")" ans
    ans="${ans:-$def}"
    [[ "$ans" =~ ^[Yy] ]]
}

# Value prompt with a default. Echoes the chosen value on stdout (prompt goes to
# stderr so it stays out of command substitution).
ask_val() {
    local q="$1" def="$2" ans
    [ "$INTERACTIVE" = 0 ] && { printf '%s' "$def"; return; }
    read -rp "$(printf '\033[1;36m? %s [%s]: \033[0m' "$q" "$def")" ans
    printf '%s' "${ans:-$def}"
}

have() { command -v "$1" >/dev/null 2>&1; }
pkg()  { pacman -Q "$1" >/dev/null 2>&1; }

# --- sanity checks -----------------------------------------------------------
[ "$(id -u)" = 0 ] && { c_err "❌ Don't run this as root. Run as your normal user."; exit 1; }
have git || { c_err "❌ git is not installed (sudo pacman -S git)."; exit 1; }

# The base is "installed" only if BOTH the CLI and quickshell exist — CachyOS
# images can ship the caelestia CLI alone, and the shell can't run without qs.
base_ok() { have caelestia && have qs; }

# Already got my fork AND a working base? Just update instead. -----------------
if [ -e "$REPO/.git" ] && base_ok; then
    c_info "📦 my-caelestia is already installed — updating instead..."
    exec "$REPO/personal/update.sh"
fi

# Need an AUR helper ----------------------------------------------------------
HELPER="$(command -v paru || command -v yay || true)"
if [ -z "$HELPER" ]; then
    c_err "❌ Need an AUR helper (paru or yay) and couldn't find one."
    c_err "   CachyOS ships paru by default; otherwise install one first, then re-run."
    exit 1
fi
HELPER_NAME="$(basename "$HELPER")"

# --- show what's already here (so nothing gets installed twice) --------------
c_info "🔍 Checking what's already on this machine..."
base_ok                    && c_ok "  ✔ Caelestia + quickshell installed (base install will be skipped)" || c_warn "  • Caelestia base (shell/quickshell) incomplete — will install it"
have linux-wallpaperengine && c_ok "  ✔ Wallpaper Engine renderer present"                 || echo  "  • Wallpaper Engine renderer not installed"
pkg caelestia-sddm-locklike-git && c_ok "  ✔ SDDM login theme present"                      || echo  "  • SDDM login theme not installed"
have ollama               && c_ok "  ✔ Ollama present (AI page will work)"                  || echo  "  • Ollama not installed (needed only for the AI page)"

# --- feature selection -------------------------------------------------------
c_info "🧩 Pick the optional features you want (anything already installed is reused, not reinstalled):"
WANT_WE=y;   ask "Wallpaper Engine support (live wallpapers in the picker)?" y || WANT_WE=n
WANT_SDDM=y; ask "Matching SDDM login screen theme?"                         y || WANT_SDDM=n
WANT_AI=y;   ask "AI assistant page (installs Ollama, runs fully locally)?"  y || WANT_AI=n

# --- personal settings (written to local overrides; repo stays untouched) ----
c_info "⚙️  A couple of personal settings (press Enter to keep the default):"
KB="$(ask_val 'Keyboard layout' 'de')"
DEF_WALL="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Wallpapers"
WALL="$(ask_val 'Wallpaper folder' "$DEF_WALL")"

# --- sudo keepalive ----------------------------------------------------------
c_info "🔑 This needs your sudo password (once)..."
sudo -v || { c_err "❌ sudo failed."; exit 1; }
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT

# --- low-RAM guard ------------------------------------------------------------
# AUR builds (quickshell, the caelestia-shell plugin) run one C++ compiler per
# core, each needing 1-2 GB. In a small VM the kernel OOM-kills cc1plus and the
# build dies with "fatal error: Signal Getötet/Killed". Cap jobs to ~RAM/2GB.
MEM_GB="$(awk '/MemTotal/{printf "%d", $2/1048576}' /proc/meminfo 2>/dev/null || echo 8)"
JOBS=$(( MEM_GB / 2 )); [ "$JOBS" -lt 1 ] && JOBS=1
NPROC="$(nproc 2>/dev/null || echo "$JOBS")"
[ "$JOBS" -gt "$NPROC" ] && JOBS="$NPROC"
if [ "$JOBS" -lt "$NPROC" ]; then
    c_warn "🧠 Only ${MEM_GB}GB RAM — capping builds to $JOBS parallel job(s) so the compiler isn't OOM-killed."
    c_warn "   (More RAM = faster install. 8GB+ recommended just for the build.)"
    export MAKEFLAGS="-j$JOBS" CMAKE_BUILD_PARALLEL_LEVEL="$JOBS" NINJAFLAGS="-j$JOBS"
fi

# --- 1. Caelestia base (only if missing) -------------------------------------
# caelestia-shell (AUR) pulls in everything the shell needs: caelestia-cli,
# quickshell-git, fonts, and all runtime tools. Hyprland comes from the repos.
if base_ok; then
    c_ok "✅ Caelestia already installed — skipping base install."
else
    c_step "Installing Caelestia (Hyprland, shell, quickshell, fonts — this takes a while)..."
    "$HELPER" -S --needed --noconfirm hyprland xdg-desktop-portal-hyprland caelestia-shell \
        || { c_err "❌ Base install failed — fix the error above and re-run."; exit 1; }
    base_ok || { c_err "❌ Base install finished but 'caelestia'/'qs' still missing — something is off."; exit 1; }
fi

# --- 2. selected extras (--needed = skips anything already installed) --------
EXTRAS=()
[ "$WANT_WE" = y ]   && EXTRAS+=(linux-wallpaperengine-git)
[ "$WANT_SDDM" = y ] && EXTRAS+=(caelestia-sddm-locklike-git)
[ "$WANT_AI" = y ]   && EXTRAS+=(ollama)
if [ "${#EXTRAS[@]}" -gt 0 ]; then
    c_step "Installing selected extras: ${EXTRAS[*]}"
    "$HELPER" -S --needed --noconfirm "${EXTRAS[@]}" \
        || c_warn "   (an extra failed to build — non-fatal, your desktop still works)"
fi
if [ "$WANT_AI" = y ] && have ollama; then
    sudo systemctl enable --now ollama 2>/dev/null \
        || c_warn "   (couldn't start the ollama service; start it later with: sudo systemctl enable --now ollama)"
    c_warn "   The AI page needs a model — pull one later with e.g.:  ollama pull llama3.2"
fi

# --- 3. layer my fork over the package shell ---------------------------------
if [ -e "$REPO/.git" ] && [ "$(git -C "$REPO" remote get-url origin 2>/dev/null)" = "$URL" ]; then
    c_step "My shell fork is already cloned — updating it..."
    git -C "$REPO" pull -q --ff-only || c_warn "   (couldn't fast-forward — keeping the existing checkout)"
else
    if [ -e "$REPO" ]; then
        mv "$REPO" "$REPO.before-mine.bak"
        c_warn "📁 Moved existing $REPO aside to $(basename "$REPO").before-mine.bak"
    fi
    c_step "Installing my shell fork..."
    git clone -q "$URL" "$REPO"
fi
cd "$REPO"
git remote add upstream "$UPSTREAM" 2>/dev/null || true
git fetch -q upstream --tags 2>/dev/null || true

# --- 4. link my config + install the rice-update command ---------------------
c_step "Linking my config + installing the 'rice-update' command..."
"$REPO/personal/install.sh"

# --- 5. apply personal settings WITHOUT polluting the repo -------------------
# Hyprland variables override file is untracked and auto-merged over variables.lua.
mkdir -p "$CFG/caelestia"
if [ "$KB" != "de" ]; then
    printf 'return {\n    kbLayout = "%s",\n}\n' "$KB" > "$CFG/caelestia/hypr-vars.lua"
    c_ok "  ⌨️  keyboard layout set to '$KB' (saved in hypr-vars.lua)"
fi
# Wallpaper folder: create it, and if it differs from the repo default, swap the
# symlinked shell.json for a patched local copy so the tracked repo file is left
# alone (this machine just won't auto-pull future shell.json changes).
mkdir -p "$WALL"
if have python3; then
    REPO_WALL="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("paths",{}).get("wallpaperDir",""))' \
        "$REPO/personal/config/caelestia/shell.json" 2>/dev/null || true)"
    REPO_WALL="${REPO_WALL/#\~/$HOME}"
    if [ "$WALL" != "$REPO_WALL" ]; then
        sj="$CFG/caelestia/shell.json"; tmp="$(mktemp)"
        if python3 - "$sj" "$WALL" >"$tmp" <<'PY'
import json,sys
p,wall=sys.argv[1],sys.argv[2]
d=json.load(open(p)); d.setdefault("paths",{})["wallpaperDir"]=wall
json.dump(d,sys.stdout,indent=4)
PY
        then
            rm -f "$sj"; mv "$tmp" "$sj"
            c_ok "  🖼️  wallpaper folder set to '$WALL' (shell.json is now a local copy on this machine)"
        else
            rm -f "$tmp"; c_warn "   (couldn't patch shell.json wallpaper folder — set it in the GUI later)"
        fi
    fi
fi

# --- 6. start it now if we're already in a graphical session -----------------
if [ -n "${WAYLAND_DISPLAY:-}" ] && have qs; then
    c_info "🔄 Starting the shell..."
    qs -c caelestia kill >/dev/null 2>&1; sleep 1
    ( setsid caelestia shell -d >/dev/null 2>&1 & )
    c_ok "🎉 All done! Your full rice is installed and running."
else
    c_ok "🎉 All done! Your full rice is installed."
    c_warn "   Log into a Hyprland session to see it (the shell autostarts there)."
fi
[ "$WANT_SDDM" = y ] && c_warn "   For the matching login screen, enable SDDM and select the 'caelestia' theme."
echo
c_ok "From now on, update anytime with:  rice-update"

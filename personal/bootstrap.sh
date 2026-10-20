#!/usr/bin/env bash
#
# FULL one-command install of my rice on a fresh Arch/CachyOS machine.
# Installs Caelestia itself (only if missing), the extras my setup uses (you pick
# which), then layers my fork + config on top. Safe to re-run — anything already
# present is detected and skipped (never installed twice).
#
#   curl -fsSL https://raw.githubusercontent.com/0Inexis0/my-caelestia/main/personal/bootstrap.sh -o /tmp/rice.sh && bash /tmp/rice.sh
#
# (Run it from a normal terminal/TTY as your user — NOT as root. It asks for your
#  sudo password once. Piping straight into bash works too, but then it can't ask
#  questions; use --dry-run to preview and --yes to accept the default selection.)
#
set -euo pipefail

DATA="${XDG_DATA_HOME:-$HOME/.local/share}/my-caelestia"
REPO="$DATA/source"
LEGACY="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"
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

# Quiet execution for non-interactive commands; prompts stay outside this wrapper.
INSTALL_LOG=''
run_step() {
    local label="$1" pid rc=0 tick=0 latest count total percent
    shift
    printf '\n$ ' >> "$INSTALL_LOG"
    printf '%q ' "$@" >> "$INSTALL_LOG"
    printf '\n' >> "$INSTALL_LOG"
    [ -t 1 ] || printf '  [···] %s\n' "$label"
    local offset
    offset=$(wc -l < "$INSTALL_LOG")
    NINJA_STATUS='[rice:%f/%t] ' "$@" >> "$INSTALL_LOG" 2>&1 &
    pid=$!
    trap 'kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; exit 130' INT TERM
    while kill -0 "$pid" 2>/dev/null; do
        if [ -t 1 ]; then
            latest=$(tail -n +"$((offset+1))" "$INSTALL_LOG" | tail -n 6 | sed -n 's/.*\[rice:\([0-9]*\)\/\([0-9]*\)\].*/\1 \2/p' | tail -n 1)
            if [ -n "$latest" ]; then
                read -r count total <<< "$latest"
                percent=$((100 * count / (total > 0 ? total : 1)))
                printf '\r\033[2K  [%-20s] %s · %s/%s · %s%%' "$(printf '%*s' "$((percent/5))" '' | tr ' ' '=')" "$label" "$count" "$total" "$percent"
            else
                printf '\r\033[2K  [%s] %s' "${FRAMES:$((tick%4)):1}" "$label"
            fi
        fi
        tick=$((tick+1))
        sleep 0.2
    done
    wait "$pid" || rc=$?
    trap - INT TERM
    [ ! -t 1 ] || printf '\r\033[2K'
    if [ "$rc" -ne 0 ]; then
        c_err "  ✗ $label"
        tail -n +"$((offset+1))" "$INSTALL_LOG" | tail -n 45 >&2
        c_err "Details: $INSTALL_LOG"
        return "$rc"
    fi
    c_ok "  ✓ $label"
}
FRAMES='|/-\\'

preflight() {
    local ID='' ID_LIKE='' PRETTY_NAME='' mem available target
    . /etc/os-release
    case " $ID $ID_LIKE " in
        *' arch '*|*' cachyos '*) ;;
        *) c_err 'Supported: Arch Linux / CachyOS (or Arch derivatives).'; return 1 ;;
    esac
    for tool in git curl sudo pacman timeout df awk; do
        have "$tool" || { c_err "Required command missing: $tool"; return 1; }
    done
    mem=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
    [ "$mem" -ge 2048 ] || { c_err 'At least 2 GiB RAM is required for local builds.'; return 1; }
    [ "$mem" -ge 8192 ] || c_warn 'Less than 8 GiB RAM: builds will be slower; parallel jobs are limited.'
    # Check nearest existing parent; no directories are created during preview.
    target="$DATA"
    while [ ! -d "$target" ]; do target=$(dirname "$target"); done
    available=$(df -Pk "$target" | awk 'END{print $4}')
    [ "$available" -ge 12582912 ] || { c_err 'Need at least 12 GiB free on the build/data filesystem.'; return 1; }
    available=$(df -Pk / | awk 'END{print $4}')
    [ "$available" -ge 6291456 ] || { c_err 'Need at least 6 GiB free on the system filesystem.'; return 1; }
    timeout 20 git ls-remote --exit-code "$URL" refs/heads/main >/dev/null 2>&1 || {
        c_err 'Cannot reach the main branch on GitHub. Check the network.'; return 1;
    }
    curl -fsS --connect-timeout 10 --max-time 20 https://aur.archlinux.org/ -o /dev/null || {
        c_err 'Cannot reach the AUR. Check the network.'; return 1;
    }
    c_ok "Preflight OK: $PRETTY_NAME · ${mem} MiB RAM · disk space and network available"
    for target in "$CFG/hypr" "$CFG/caelestia" "$LEGACY"; do
        [ ! -e "$target" ] || c_warn "Existing configuration: $target (regular files are backed up before linking)."
    done
}

confirm_plan() {
    if [ "$DRY_RUN" = 1 ]; then
        c_ok 'Preview only — nothing installed or changed.'
        exit 0
    fi
    if [ "$ASSUME_YES" != 1 ]; then
        [ "$INTERACTIVE" = 1 ] || { c_err 'Review with --dry-run, then run with --yes or from a terminal.'; exit 1; }
        ask 'Proceed with this installation?' n || { c_info 'Cancelled — no changes made.'; exit 0; }
    fi
    mkdir -p "$DATA/logs"
    INSTALL_LOG="$DATA/logs/install-$(date +%Y%m%d-%H%M%S)-$$.log"
    touch "$INSTALL_LOG"
    c_info "Installation log: $INSTALL_LOG"
}

DRY_RUN=0; ASSUME_YES=0
FORWARD_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --yes) ASSUME_YES=1 ;;
        --help|-h) printf 'Usage: bash bootstrap.sh [--dry-run] [--yes]\nPreview performs checks without installing. --yes accepts the installation plan.\n'; exit 0 ;;
        *) FORWARD_ARGS+=("$arg") ;;
    esac
done

# --- sanity checks -----------------------------------------------------------
[ "$(id -u)" = 0 ] && { c_err "❌ Don't run this as root. Run as your normal user."; exit 1; }
have git || { c_err "❌ git is not installed (sudo pacman -S git)."; exit 1; }

# The base is "installed" only if the CLI, quickshell, Hyprland AND the shell
# package's compiled QML plugin all exist. Checking any less lies: CachyOS
# images ship the caelestia CLI alone, and quickshell can be present while the
# caelestia-shell package (which provides the plugin) never got built.
# CachyOS ships `noctalia-qs`, which declares provides=(quickshell quickshell-git)
# and installs its own /usr/bin/qs. It satisfies caelestia-shell's dependency on
# the *name* quickshell-git, but bundles a quickshell older than the shell needs,
# so every config — ours and /etc/xdg's — then dies at launch with
# `Unrecognized pragma "DefaultEnv ..."`. Only the real AUR package will do.
qs_is_real() { pacman -Qoq /usr/bin/qs 2>/dev/null | grep -qx quickshell-git; }
base_ok() { have caelestia && have qs && qs_is_real && have Hyprland && [ -e /usr/lib/qt6/qml/Caelestia ]; }
build_tools_ok() { have cmake && have ninja && have python3 && pkg base-devel && pkg qt6-shadertools && pkg qt6-m3shapes-git; }
UPDATE_ARGS=("${FORWARD_ARGS[@]}")
[ -n "${WAYLAND_DISPLAY:-}" ] || UPDATE_ARGS+=(--no-restart)

prepare_main() {
    local repo="$1" branch
    branch="$(git -C "$repo" branch --show-current)"
    case "$branch" in
        main) ;;
        mine) git -C "$repo" branch -m main || return 1 ;;
        *) c_err "Switch $repo to main before installing."; return 1 ;;
    esac
    if [ -n "$(git -C "$repo" status --porcelain)" ]; then
        git -C "$repo" add -A && git -C "$repo" commit -m "Save local changes before bootstrap" || return 1
    fi
    git -C "$repo" fetch origin main || return 1
    git -C "$repo" merge --ff-only origin/main || return 1
    git -C "$repo" branch --set-upstream-to=origin/main main
}

preflight

# Use the current manager even when upgrading an older checkout.
if [ -e "$REPO/.git" ] && base_ok && build_tools_ok; then
    c_info "Plan: update existing main checkout at $REPO; build, verify and activate the shell."
    c_info 'Existing personal configuration is retained. System updates use the updater defaults.'
    confirm_plan
    run_step 'Prepare main checkout' prepare_main "$REPO" || exit 1
    exec "$REPO/personal/update.sh" "${UPDATE_ARGS[@]}"
fi
if [ -d "$LEGACY/.git" ] && base_ok && build_tools_ok; then
    c_info "Plan: preserve and migrate $LEGACY to $REPO on main, then update and verify."
    confirm_plan
    # Save legacy edits before cloning so migration cannot drop them.
    if [ -n "$(git -C "$LEGACY" status --porcelain)" ]; then
        git -C "$LEGACY" add -A && git -C "$LEGACY" commit -m "Save local changes before managed migration" || exit 1
    fi
    mkdir -p "$DATA"
    git clone --no-hardlinks "$LEGACY" "$REPO" || exit 1
    git -C "$REPO" remote set-url origin "$URL" || exit 1
    prepare_main "$REPO" || {
        c_err "Local history diverged. Merge origin/main in $REPO, then run its personal/update.sh."
        exit 1
    }
    exec "$REPO/personal/update.sh" "${UPDATE_ARGS[@]}"
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
have music-discord-rpc    && c_ok "  ✔ Discord music rich presence present"                 || echo  "  • Discord music rich presence not installed"

# --- feature selection -------------------------------------------------------
c_info "🧩 Pick the optional features you want (anything already installed is reused, not reinstalled):"
WANT_WE=y;   ask "Wallpaper Engine support (live wallpapers in the picker)?" y || WANT_WE=n
WANT_SDDM=y; ask "Matching SDDM login screen theme?"                         y || WANT_SDDM=n
WANT_AI=y;   ask "AI assistant page (installs Ollama, runs fully locally)?"  y || WANT_AI=n
WANT_RPC=y;  ask "Discord Rich Presence for music (playerctl + music-discord-rpc, picks up Apple Music/Spotify/YT Music playing in your browser via MPRIS)?" y || WANT_RPC=n

# --- personal settings (written to local overrides; repo stays untouched) ----
c_info "⚙️  A couple of personal settings (press Enter to keep the default):"
KB="$(ask_val 'Keyboard layout' 'de')"
[[ "$KB" =~ ^[a-zA-Z0-9_,\ -]+$ ]] || { c_err "Invalid keyboard layout"; exit 1; }
DEF_WALL="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Wallpapers"
WALL="$(ask_val 'Wallpaper folder' "$DEF_WALL")"
if [ "$WANT_RPC" = y ]; then
    RPC_PLAYER="$(ask_val 'Browser to pull "now playing" from for Discord (MPRIS player name, e.g. Brave, firefox, chromium)' 'Brave')"
fi

# --- preview before package, Git or configuration mutations -------------------
BASE_PACKAGES=(hyprland xdg-desktop-portal-hyprland caelestia-shell)
BUILD_PACKAGES=(base-devel cmake ninja python qt6-shadertools qt6-m3shapes-git)
APP_PACKAGES=(foot wl-clipboard cliphist trash-cli gammastep polkit-gnome gnome-keyring thunar pavucontrol firefox networkmanager python-gobject)
EXTRAS=()
[ "$WANT_WE" = y ] && EXTRAS+=(linux-wallpaperengine-git)
[ "$WANT_SDDM" = y ] && EXTRAS+=(caelestia-sddm-locklike-git)
[ "$WANT_AI" = y ] && EXTRAS+=(ollama)
[ "$WANT_RPC" = y ] && EXTRAS+=(playerctl music-discord-rpc-bin)
c_info 'Installation preview'
printf '  Source: %s (main)\n  Keyboard: %s\n  Wallpapers: %s\n' "$REPO" "$KB" "$WALL"
printf '  Base: %s\n  Build tools: %s\n  Apps: %s\n  Extras: %s\n' "${BASE_PACKAGES[*]} + original quickshell-git" "${BUILD_PACKAGES[*]}" "${APP_PACKAGES[*]}" "${EXTRAS[*]:-none}"
printf '  Configuration: %s/hypr/{*.lua,scripts,monitors.d}, %s/caelestia/{shell.json,cli.json,we-*.sh,wallpaper-posthook.sh,hypr-vars.lua}\n' "$CFG" "$CFG"
printf '  Command: %s/.local/bin/rice-update\n' "$HOME"
c_warn 'Existing regular config files are backed up; existing symlinks are replaced. Selected extras may enable Ollama and Discord RPC.'
c_info 'Installed packages are reused; missing packages and their dependencies are installed. Shell build and verification follow.'
confirm_plan

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

# --- 3. layer my fork over the package shell ---------------------------------
if [ -e "$REPO/.git" ] && [ "$(git -C "$REPO" remote get-url origin 2>/dev/null)" = "$URL" ]; then
    c_step "My shell fork is already cloned — updating it..."
    run_step 'Update main checkout' prepare_main "$REPO" || exit 1
else
    if [ -e "$REPO" ]; then
        backup="$(mktemp -d "$DATA/source-backup.XXXXXX")"
        mv "$REPO" "$backup/source"
        c_warn "📁 Moved existing $REPO aside to $backup/source"
    fi
    c_step "Installing my shell fork..."
    mkdir -p "$DATA"
    run_step 'Download main checkout' git clone -q --branch main "$URL" "$REPO" || exit 1
fi
cd "$REPO"
git remote add upstream "$UPSTREAM" 2>/dev/null || true
git fetch -q upstream --tags 2>/dev/null || true

# --- 1. Caelestia base (only if missing) -------------------------------------
# caelestia-shell (AUR) pulls in everything the shell needs: caelestia-cli,
# quickshell-git, fonts, and all runtime tools. Hyprland comes from the repos.
if base_ok; then
    c_ok "✅ Caelestia already installed — skipping base install."
else
    c_step "Installing Caelestia (Hyprland, shell, quickshell, fonts — this takes a while)..."
    # Build quickshell from the AUR *first*, explicitly. caelestia-shell only
    # asks for the name `quickshell-git`, and pacman prefers a binary repo when
    # resolving that on its own — which on CachyOS silently pulls noctalia-qs
    # (see qs_is_real above) and leaves an unbootable shell. Installing the real
    # package up front means the dependency is already satisfied correctly.
    # Let the package transaction replace conflicting providers only after the
    # new package has built successfully. Never remove dependencies with -Rdd.
    run_step 'Install Python for the package builder' "$HELPER" -S --needed --noconfirm --sudoflags -n python
    python3 -c "$(cat <<'PYQS'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location('manager', pathlib.Path(sys.argv[1]) / 'personal/manage.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.LOG = pathlib.Path(sys.argv[3])
try:
    m.ensure_quickshell(pathlib.Path(sys.argv[2]))
except Exception as error:
    print(getattr(error, 'stderr', '') or '', file=sys.stderr)
    print(f'Quickshell installation failed: {error}', file=sys.stderr)
    sys.exit(1)
PYQS
)" "$REPO" "$DATA" "$INSTALL_LOG"
    run_step 'Install desktop base' "$HELPER" -S --needed --noconfirm --sudoflags -n "${BASE_PACKAGES[@]}" \
        || { c_err 'Base installation failed.'; exit 1; }
    if ! base_ok; then
        if have qs && ! qs_is_real; then
            c_err "❌ /usr/bin/qs came from $(pacman -Qoq /usr/bin/qs 2>/dev/null), not quickshell-git."
            c_err "   Install aur/quickshell-git and confirm the provider replacement."
        else
            c_err "❌ Base install finished but 'caelestia'/'qs' still missing — something is off."
        fi
        exit 1
    fi
fi

# Build tools are needed on existing installations too. Runtime libraries come
# from caelestia-shell; install new upstream dependencies explicitly here.
run_step 'Install build dependencies' "$HELPER" -S --needed --noconfirm --sudoflags -n "${BUILD_PACKAGES[@]}" \
    || { c_err "Build dependencies could not be installed."; exit 1; }

# --- 2. selected extras (--needed = skips anything already installed) --------
if [ "${#EXTRAS[@]}" -gt 0 ]; then
    c_step "Installing selected extras: ${EXTRAS[*]}"
    run_step 'Install selected extras' "$HELPER" -S --needed --noconfirm --sudoflags -n "${EXTRAS[@]}" \
        || c_warn "   (an extra failed to build — non-fatal, your desktop still works)"
fi
# --- 2b. apps my config expects (terminal keybind, clipboard, agents, ...) ----
c_step "Installing the apps the rice uses (foot terminal, clipboard history, ...)..."
run_step 'Install desktop applications' "$HELPER" -S --needed --noconfirm --sudoflags -n "${APP_PACKAGES[@]}" \
    || c_warn "   (some apps failed to install — keybinds for them just won't do anything)"

if [ "$WANT_AI" = y ] && have ollama; then
    sudo systemctl enable --now ollama 2>/dev/null \
        || c_warn "   (couldn't start the ollama service; start it later with: sudo systemctl enable --now ollama)"
    c_warn "   The AI page needs a model — pull one later with e.g.:  ollama pull llama3.2"
fi

if [ "$WANT_RPC" = y ] && have music-discord-rpc; then
    c_step "Enabling Discord music rich presence (source: $RPC_PLAYER)..."
    music-discord-rpc -a "$RPC_PLAYER" --only-when-playing enable >/dev/null 2>&1 \
        && c_ok "  ✔ Playing something in $RPC_PLAYER now shows up on Discord." \
        || c_warn "   (couldn't enable it — run manually later: music-discord-rpc -a \"$RPC_PLAYER\" --only-when-playing enable)"
fi

# --- 4. link my config + install the rice-update command ---------------------
c_step "Linking my config + installing the 'rice-update' command..."
run_step 'Link personal configuration' "$REPO/personal/install.sh" || exit 1

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

# --- 6. build and activate matching shell + plugin ----------------------------
INSTALL_ARGS=()
[ -n "${WAYLAND_DISPLAY:-}" ] || INSTALL_ARGS+=(--no-restart)
python3 "$REPO/personal/manage.py" install "${INSTALL_ARGS[@]}" || exit 1
run_step 'Final installation checks' python3 "$REPO/personal/verify-install.py"
c_ok "Installation verified. Update: rice-update · rollback: rice-update --rollback"
[ -n "${WAYLAND_DISPLAY:-}" ] || c_warn 'Graphical start was not tested from this TTY. Log into Hyprland to start the shell.'
if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
    c_warn 'The running kernel no longer has installed modules. Reboot before using the desktop.'
else
    c_info 'For new Hyprland settings, log out and log back in. Reboot if system updates require it.'
fi
c_info "Full installation log: $INSTALL_LOG"

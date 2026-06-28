#!/usr/bin/env bash
#
# FULL one-command install of my rice on a fresh Arch/CachyOS machine.
# Installs Caelestia itself (if missing), the extras my setup uses, then layers
# my fork + config on top.
#
#   curl -fsSL https://raw.githubusercontent.com/0Inexis0/my-caelestia/mine/personal/bootstrap.sh -o /tmp/rice.sh && bash /tmp/rice.sh
#
# (Run it from a normal terminal/TTY as your user — NOT as root. It will ask for
#  your sudo password once.)
#
set -uo pipefail

REPO="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"
URL="https://github.com/0Inexis0/my-caelestia.git"
UPSTREAM="https://github.com/caelestia-dots/shell.git"

c_info() { printf '\n\033[1;36m%s\033[0m\n' "$*"; }
c_ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m%s\033[0m\n' "$*"; }

if [ "$(id -u)" = 0 ]; then c_err "❌ Don't run this as root. Run as your normal user."; exit 1; fi
command -v git >/dev/null || { c_err "❌ git is not installed (sudo pacman -S git)."; exit 1; }

# Already got my fork? Just update instead. -----------------------------------
if [ -e "$REPO/.git" ]; then
    c_info "📦 my-caelestia is already installed — updating instead..."
    exec "$REPO/personal/update.sh"
fi

# Need an AUR helper -----------------------------------------------------------
HELPER="$(command -v paru || command -v yay || true)"
if [ -z "$HELPER" ]; then
    c_err "❌ Need an AUR helper (paru or yay) and couldn't find one."
    c_err "   CachyOS ships paru by default; otherwise install one first, then re-run."
    exit 1
fi
HELPER_NAME="$(basename "$HELPER")"
c_info "🔑 This needs your sudo password (once)..."
sudo -v || { c_err "❌ sudo failed."; exit 1; }
# keep sudo alive during the long install
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT

# 1. Install Caelestia itself (the big step) ----------------------------------
if command -v caelestia >/dev/null; then
    c_ok "✅ Caelestia already installed — skipping base install."
else
    c_info "📥 Installing Caelestia (packages, Hyprland, fonts — this takes a while)..."
    "$HELPER" -S --needed --noconfirm caelestia-cli
    caelestia install --noconfirm --aur-helper "$HELPER_NAME"
fi

# 2. Extras my rice uses ------------------------------------------------------
c_info "📥 Installing my extras (SDDM login theme + Wallpaper Engine renderer)..."
"$HELPER" -S --needed --noconfirm caelestia-sddm-locklike-git linux-wallpaperengine-git \
    || c_warn "   (an extra failed to build — non-fatal, your desktop still works)"

# 3. Layer my fork over the package shell -------------------------------------
if [ -e "$REPO" ]; then
    mv "$REPO" "$REPO.before-mine.bak"
    c_warn "📁 Moved existing $REPO aside to $(basename "$REPO").before-mine.bak"
fi
c_info "⬇️  Installing my shell fork..."
git clone -q "$URL" "$REPO"
cd "$REPO"
git remote add upstream "$UPSTREAM" 2>/dev/null || true
git fetch -q upstream --tags 2>/dev/null || true

c_info "🔗 Linking my config + installing the 'rice-update' command..."
"$REPO/personal/install.sh"

# 4. Start it now if we're already in a graphical session ---------------------
if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v qs >/dev/null; then
    c_info "🔄 Starting the shell..."
    qs -c caelestia kill >/dev/null 2>&1; sleep 1
    ( setsid caelestia shell -d >/dev/null 2>&1 & )
    c_ok "🎉 All done! Your full rice is installed and running."
else
    c_ok "🎉 All done! Your full rice is installed."
    c_warn "   Log into a Hyprland session to see it (the shell autostarts there)."
    c_warn "   For the matching login screen, enable SDDM with the 'caelestia' theme."
fi
echo
c_ok "From now on, update anytime with:  rice-update"

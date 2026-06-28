#!/usr/bin/env bash
#
# One-command install of my-caelestia on a fresh machine.
#
#   curl -fsSL https://raw.githubusercontent.com/0Inexis0/my-caelestia/mine/personal/bootstrap.sh | bash
#
# Assumes Caelestia itself is already installed (dotfiles + the caelestia-shell
# package). See: https://github.com/caelestia-dots/caelestia
#
set -uo pipefail

REPO="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"
URL="https://github.com/0Inexis0/my-caelestia.git"

c_info() { printf '\n\033[1;36m%s\033[0m\n' "$*"; }
c_ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m%s\033[0m\n' "$*"; }

command -v git >/dev/null || { c_err "❌ git is not installed."; exit 1; }

if [ -e "$REPO/.git" ]; then
    c_info "📦 my-caelestia is already here — updating instead..."
    exec "$REPO/personal/update.sh"
fi

if [ -e "$REPO" ]; then
    mv "$REPO" "$REPO.before-mine.bak"
    c_info "📁 Moved existing $REPO aside to $(basename "$REPO").before-mine.bak"
fi

c_info "⬇️  Downloading my-caelestia..."
git clone -q "$URL" "$REPO"
cd "$REPO"
git remote add upstream https://github.com/caelestia-dots/shell.git 2>/dev/null || true
git fetch -q upstream --tags 2>/dev/null || true

c_info "🔗 Linking your config into place..."
"$REPO/personal/install.sh"

c_info "🔄 Starting the shell..."
qs -c caelestia kill >/dev/null 2>&1; sleep 1
( setsid caelestia shell -d >/dev/null 2>&1 & )

c_ok "🎉 Done! Your rice is installed. Update anytime with:  rice-update"

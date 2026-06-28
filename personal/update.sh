#!/usr/bin/env bash
#
# Update my-caelestia while keeping ALL my own changes. Safe by design:
#   * your edits are auto-saved first (never lost)
#   * the shell is only ever synced to the Caelestia version actually installed
#     on this machine, so it can't get out of step with the system plugin
#   * if the shell fails to come back up, it rolls back automatically
#
# Just run:  rice-update
#
# To pull a *newer* Caelestia: do your normal system update first (`yay`),
# then run rice-update to bring the shell in line.
#
set -uo pipefail

REPO="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"

c_info() { printf '\n\033[1;36m%s\033[0m\n' "$*"; }
c_ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m%s\033[0m\n' "$*"; }

cd "$REPO" 2>/dev/null || { c_err "❌ Can't find your shell at $REPO"; exit 1; }

restart_shell() {
    qs -c caelestia kill >/dev/null 2>&1
    sleep 1
    ( setsid caelestia shell -d >/dev/null 2>&1 & )
}

# 1. Save anything you've changed so it can never be lost ----------------------
c_info "💾 Saving your current setup..."
git add -A
if git commit -q -m "autosave before update ($(date '+%Y-%m-%d %H:%M'))" 2>/dev/null; then
    c_ok "   saved your latest tweaks"
else
    echo "   (nothing new to save)"
fi
SAFE_POINT="$(git rev-parse HEAD)"

# 2. Which Caelestia version is installed on this machine? ----------------------
c_info "⬇️  Checking for updates..."
git fetch -q upstream --tags 2>/dev/null || { c_err "❌ Couldn't reach GitHub (internet?)."; exit 1; }

VER="$(pacman -Q caelestia-shell 2>/dev/null | awk '{print $2}' | sed 's/-[0-9]\+$//')"
if [ -n "$VER" ] && git rev-parse -q --verify "refs/tags/v$VER" >/dev/null 2>&1; then
    TAG="v$VER"                       # sync the shell to the installed version
else
    # package not found / no matching tag — fall back to the newest stable tag
    TAG="$(git -c versionsort.suffix=- tag --sort=-v:refname \
           | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
    c_warn "   (couldn't match the installed package; using newest release $TAG)"
fi
[ -n "$TAG" ] || { c_err "❌ No release found to update to."; exit 1; }

if git merge-base --is-ancestor "$TAG" HEAD; then
    c_ok "✅ Already up to date ($TAG). Nothing to do!"
    c_warn "   Want a newer Caelestia? Run a system update first:  yay"
    exit 0
fi

# 3. Merge it in, keeping your changes -----------------------------------------
c_info "🔀 Updating the shell to $TAG (keeping all your changes)..."
if ! git merge --no-edit "$TAG" >/dev/null 2>&1; then
    c_warn "⚠️  Your changes and the new version touch the same code."
    git merge --abort 2>/dev/null
    git reset -q --hard "$SAFE_POINT"
    c_err "   Nothing changed — you're still on your working version."
    c_err "   Ask Claude to do this update (it needs a manual merge)."
    exit 1
fi

# 4. Restart and confirm it actually came back up ------------------------------
c_info "🔄 Restarting your shell..."
restart_shell
sleep 4
if pgrep -f "qs -c caelestia" >/dev/null 2>&1; then
    c_ok "🎉 Updated to $TAG and your desktop is running. All done!"
else
    c_warn "⚠️  The shell didn't come back — rolling back to be safe..."
    git reset -q --hard "$SAFE_POINT"
    restart_shell
    sleep 3
    c_err "   Rolled back to your previous working version (nothing lost)."
    c_err "   Tip: run a full system update (yay), then try rice-update again,"
    c_err "   or just ask Claude."
fi

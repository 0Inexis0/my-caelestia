#!/usr/bin/env bash
#
# Update my-caelestia, keeping ALL my changes — and NEVER leave the desktop dead.
#
# Safety layers:
#   1. auto-saves your edits to git first (never lost)
#   2. rebases your changes onto the Caelestia version installed on this machine
#   3. test-loads the result in a throwaway instance BEFORE switching to it
#   4. if anything fails, rolls back; and if even the rollback won't load,
#      falls back to the system package shell so your desktop still works
#
# Run:  rice-update
# Newer Caelestia? Do a system update first (`yay`), then run this.
#
set -uo pipefail

REPO="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"
RUNDIR="/run/user/$(id -u)/quickshell/by-id"

c_info() { printf '\n\033[1;36m%s\033[0m\n' "$*"; }
c_ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m%s\033[0m\n' "$*"; }

cd "$REPO" 2>/dev/null || { c_err "❌ Can't find your shell at $REPO"; exit 1; }

restart_shell() {
    qs -c caelestia kill >/dev/null 2>&1
    sleep 1
    ( setsid caelestia shell -d >/dev/null 2>&1 & )
    sleep 4
}

# Is a caelestia shell running AND free of load errors?
shell_healthy() {
    pgrep -f "qs -c caelestia" >/dev/null 2>&1 || return 1
    local log; log="$(ls -t "$RUNDIR"/*/log.qslog 2>/dev/null | head -1)"
    [ -n "$log" ] && grep -qiE "Failed to load|unavailable|is not a type" "$log" && return 1
    return 0
}

# Load the repo in a throwaway instance and report whether it loads cleanly
test_load_ok() {
    local tlog="/tmp/rice-update-test.$$.log"
    timeout 9 qs -p "$REPO/shell.qml" -n >"$tlog" 2>&1 &
    local p=$!; sleep 8
    kill "$p" >/dev/null 2>&1
    if grep -qiE "Failed to load|unavailable|is not a type" "$tlog"; then rm -f "$tlog"; return 1; fi
    grep -qi "Configuration Loaded" "$tlog"; local r=$?
    rm -f "$tlog"; return $r
}

# Last resort: run the unmodified system package shell so the desktop works
package_fallback() {
    c_warn "🛟 Falling back to the system shell so your desktop keeps working..."
    qs -c caelestia kill >/dev/null 2>&1; sleep 1
    mv "$REPO" "$REPO.broken-$(date +%s).bak"
    ( setsid caelestia shell -d >/dev/null 2>&1 & ); sleep 4
    c_err "   Your customizations are paused (saved in the .broken-*.bak folder)."
    c_err "   Ask Claude to finish the update — nothing is lost."
}

# 1. Save your work ------------------------------------------------------------
c_info "💾 Saving your current setup..."
git add -A
git commit -q -m "autosave before update ($(date '+%Y-%m-%d %H:%M'))" 2>/dev/null \
    && c_ok "   saved" || echo "   (nothing new to save)"
SAFE_POINT="$(git rev-parse HEAD)"

# 2. Target = the Caelestia version installed on this machine ------------------
c_info "⬇️  Checking for updates..."
git fetch -q upstream --tags 2>/dev/null || { c_err "❌ Couldn't reach GitHub (internet?)."; exit 1; }
VER="$(pacman -Q caelestia-shell 2>/dev/null | awk '{print $2}' | sed 's/-[0-9]\+$//')"
if [ -n "$VER" ] && git rev-parse -q --verify "refs/tags/v$VER" >/dev/null 2>&1; then
    TAG="v$VER"
else
    TAG="$(git -c versionsort.suffix=- tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
    c_warn "   (couldn't match the installed package; using newest release $TAG)"
fi
[ -n "$TAG" ] || { c_err "❌ No release found."; exit 1; }

if git merge-base --is-ancestor "$TAG" HEAD; then
    if shell_healthy; then c_ok "✅ Already up to date ($TAG) and running fine. Nothing to do!"; exit 0; fi
    c_warn "Already on $TAG but the shell isn't healthy — restarting..."
    restart_shell; shell_healthy && { c_ok "✅ Back up and running."; exit 0; } || { package_fallback; exit 1; }
fi

# 3. Rebase your changes onto the new version ---------------------------------
c_info "🔀 Updating to $TAG (keeping all your changes)..."
OLDBASE="$(git merge-base HEAD "$TAG")"
rebase_failed=0
if ! git rebase --onto "$TAG" "$OLDBASE" mine >/dev/null 2>&1; then
    # auto-resolve README-only conflicts (we always want our README); bail on any code conflict
    while [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; do
        conflicts="$(git diff --name-only --diff-filter=U)"
        if [ "$conflicts" = "README.md" ]; then
            git checkout --theirs README.md >/dev/null 2>&1; git add README.md
            GIT_EDITOR=true git rebase --continue >/dev/null 2>&1 || true
        else
            rebase_failed=1; git rebase --abort >/dev/null 2>&1; break
        fi
    done
fi
if [ "$rebase_failed" = 1 ]; then
    git reset -q --hard "$SAFE_POINT"
    c_warn "⚠️  Your changes clash with $TAG and need a manual merge."
    restart_shell; shell_healthy || package_fallback
    c_err "   Ask Claude to do this update."
    exit 1
fi

# 4. Test-load BEFORE switching the live shell --------------------------------
c_info "🧪 Testing the update before applying it..."
if ! test_load_ok; then
    c_warn "⚠️  The updated shell didn't load cleanly — keeping your current version."
    git reset -q --hard "$SAFE_POINT"
    restart_shell; shell_healthy || package_fallback
    c_err "   Ask Claude to look at it."
    exit 1
fi

# 5. Apply it ------------------------------------------------------------------
c_info "🔄 Restarting your shell..."
restart_shell
if shell_healthy; then
    c_ok "🎉 Updated to $TAG and your desktop is running. All done!"
    git push --force-with-lease origin mine >/dev/null 2>&1 && c_ok "   (synced to GitHub)" || true
else
    c_warn "⚠️  Shell didn't come back — rolling back..."
    git reset -q --hard "$SAFE_POINT"
    restart_shell; shell_healthy || package_fallback
    c_err "   Rolled back. Ask Claude."
fi

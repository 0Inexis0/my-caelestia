#!/usr/bin/env bash
#
# Update everything in one shot, keeping ALL my changes — and NEVER leave the
# desktop dead.
#
# What it does:
#   0. updates your system packages (yay -Syu: Caelestia, quickshell, etc.)
#   1. auto-saves your edits to git first (never lost)
#   2. rebases your changes onto the now-installed Caelestia version
#   3. test-loads the result in a throwaway instance BEFORE switching to it
#   4. if anything fails, rolls back; and if even the rollback won't load,
#      falls back to the system package shell so your desktop still works
#
# Run:  rice-update                 (does the system update too)
#       rice-update --skip-system   (just sync the shell, no package update)
#
set -uo pipefail

REPO="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"
RUNDIR="/run/user/$(id -u)/quickshell/by-id"

DO_SYSTEM=1
for a in "$@"; do case "$a" in -s|--skip-system) DO_SYSTEM=0 ;; esac; done

c_info() { printf '\n\033[1;36m%s\033[0m\n' "$*"; }
c_ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m%s\033[0m\n' "$*"; }

cd "$REPO" 2>/dev/null || { c_err "❌ Can't find your shell at $REPO"; exit 1; }

# Refuse to "update" onto a machine whose Caelestia base never finished
# installing — that's the bootstrap's job, not ours.
if ! command -v qs >/dev/null 2>&1 || [ ! -e /usr/lib/qt6/qml/Caelestia ]; then
    c_err "❌ The Caelestia base (quickshell / caelestia-shell package) is incomplete on this machine."
    c_err "   Re-run the bootstrap to finish installing it:"
    c_err "   curl -L tinyurl.com/my-caelestia -o r; bash r"
    exit 1
fi

# Full system update via the AUR helper (keeps Caelestia + quickshell in step)
system_update() {
    local helper; helper="$(command -v yay || command -v paru || true)"
    if [ -z "$helper" ]; then
        c_warn "   (no yay/paru found — skipping the package update)"
        return
    fi
    c_info "📦 Updating system packages (Caelestia, quickshell, everything)..."
    c_warn "   This will ask for your password and confirmations — that's normal."
    "$helper" -Syu || c_warn "   (system update didn't finish cleanly — continuing with the shell sync)"
}

restart_shell() {
    qs -c caelestia kill >/dev/null 2>&1
    sleep 1
    ( setsid caelestia shell -d >/dev/null 2>&1 & )
    sleep 4
}

ERRPAT="Failed to load|unavailable|is not a type"

# Is a caelestia shell running AND free of load errors?
# The .qslog files are a binary format, so they have to be decoded with
# `qs log` — grepping the raw file never matches anything.
shell_healthy() {
    pgrep -f "qs -c caelestia" >/dev/null 2>&1 || return 1
    local log; log="$(ls -t "$RUNDIR"/*/log.qslog 2>/dev/null | head -1)"
    [ -n "$log" ] || return 0
    qs log -t 200 "$log" 2>/dev/null | grep -qiE "$ERRPAT" && return 1
    return 0
}

# Load the repo in a throwaway instance and report whether it loads cleanly.
# Quickshell identifies an instance by its config path, so this has to run from
# a scratch copy: pointed at $REPO itself, `-n` sees the live shell and exits
# immediately ("An instance of this configuration is already running"), which
# looks exactly like a failed load and rolls back a perfectly good update.
test_load_ok() {
    local tlog tdir r=0
    tlog="$(mktemp /tmp/rice-update-test.XXXXXX.log)"
    tdir="$(mktemp -d /tmp/rice-update-test.XXXXXX)"
    if ! cp -a "$REPO/." "$tdir/" 2>/dev/null; then
        rm -rf "$tdir" "$tlog"; return 0   # can't test — don't block the update
    fi
    rm -rf "$tdir/.git"

    timeout 20 qs -p "$tdir/shell.qml" -n >"$tlog" 2>&1 &
    local p=$!
    # Stop as soon as it has loaded (usually ~1s) instead of always waiting.
    local i=0
    while [ $i -lt 30 ]; do
        grep -qi "Configuration Loaded" "$tlog" && break
        grep -qiE "$ERRPAT" "$tlog" && break
        sleep 0.5; i=$((i + 1))
    done
    kill "$p" >/dev/null 2>&1

    if grep -qiE "$ERRPAT" "$tlog" || ! grep -qi "Configuration Loaded" "$tlog"; then
        r=1
        cp "$tlog" /tmp/rice-update-last-failure.log 2>/dev/null
        c_warn "   (details: /tmp/rice-update-last-failure.log)"
    fi
    rm -rf "$tdir" "$tlog"
    return $r
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
git add -A >/dev/null 2>&1
if git commit -q -m "autosave before update ($(date '+%Y-%m-%d %H:%M'))" >/dev/null 2>&1; then
    c_ok "   saved"
else
    echo "   (nothing new to save)"
fi
SAFE_POINT="$(git rev-parse HEAD)"

# 1b. Update system packages first (so the shell can sync to the new version) --
[ "$DO_SYSTEM" = 1 ] && system_update

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
    while [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; do
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

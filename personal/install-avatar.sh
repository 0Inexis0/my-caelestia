#!/usr/bin/env bash
# Supply a neutral default without replacing a user's own profile picture.
set -euo pipefail
PERSONAL="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -e "$HOME/.face" && ! -L "$HOME/.face" && ! -e "$HOME/.face.icon" && ! -L "$HOME/.face.icon" ]]; then
    install -m 0644 "$PERSONAL/../assets/user.svg" "$HOME/.face"
    echo 'Installed neutral profile picture (~/.face).'
fi

THEME=/usr/share/sddm/themes/caelestia
if [[ -d "$THEME/assets" ]]; then
    # During bootstrap sudo is already authenticated. On an existing machine,
    # --sync-sddm lets the user authenticate in their own terminal.
    if [[ "${1:-}" == --sync-sddm ]] || sudo -n true 2>/dev/null; then
        for name in .face .face.icon; do
            if [[ -f "$HOME/$name" ]]; then
                sudo install -m 0644 "$HOME/$name" "$THEME/assets/avatar$name"
            fi
        done
        echo 'SDDM profile picture synced.'
    else
        printf 'SDDM sync needs authentication. Run: bash %q --sync-sddm\n' "$PERSONAL/install-avatar.sh"
    fi
fi

#!/usr/bin/env bash
# Update the managed source, build the matching plugin, validate, then activate.
set -euo pipefail
PERSONAL="$(dirname "$(readlink -f "$0")")"
if [ "${1:-}" = --rollback ]; then
    shift
    exec python3 "$PERSONAL/manage.py" rollback "$@"
fi
exec python3 "$PERSONAL/manage.py" update "$@"

#!/bin/sh
set -eu

fail() {
    printf '%s\n' "[devkit-wulf] $*" >&2
    exit 2
}

[ "$(uname -s 2>/dev/null || printf unknown)" = "AIX" ] || fail "This entrypoint is for AIX only."

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -P "$SCRIPT_DIR/../.." && pwd)
CORE="$ROOT_DIR/bin/devkit-wulf"
[ -f "$CORE" ] || fail "POSIX orchestrator core not found: $CORE"
[ -x "$CORE" ] || fail "POSIX orchestrator core is not executable: $CORE"

exec "$CORE" "$@"

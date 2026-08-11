#!/bin/sh
set -eu

fail() {
    printf '%s\n' "[devkit-wulf] $*" >&2
    exit 2
}

[ "$(uname -s 2>/dev/null || printf unknown)" = "Linux" ] || fail "This entrypoint is for native Linux only."

for marker in /proc/sys/kernel/osrelease /proc/version; do
    if [ -r "$marker" ] && grep -Eiq '(microsoft|wsl)' "$marker"; then
        fail "WSL detected. Use installers/wsl/devkit-wulf.sh inside the WSL distribution."
    fi
done

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -P "$SCRIPT_DIR/../.." && pwd)
CORE="$ROOT_DIR/bin/devkit-wulf"
[ -f "$CORE" ] || fail "POSIX orchestrator core not found: $CORE"
[ -x "$CORE" ] || fail "POSIX orchestrator core is not executable: $CORE"

exec "$CORE" "$@"

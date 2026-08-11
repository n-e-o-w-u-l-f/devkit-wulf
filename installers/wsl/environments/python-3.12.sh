#!/bin/sh
set -eu

fail() {
    printf '%s\n' "[devkit-wulf][python-3.12] $*" >&2
    exit 2
}

[ "$(uname -s 2>/dev/null || printf unknown)" = "Linux" ] || fail "This adapter must run inside WSL Linux."

is_wsl=0
for marker in /proc/sys/kernel/osrelease /proc/version; do
    if [ -r "$marker" ] && grep -Eiq '(microsoft|wsl)' "$marker"; then
        is_wsl=1
        break
    fi
done
[ "$is_wsl" -eq 1 ] || fail "WSL was not detected. Use the native Linux adapter on native Linux."

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
LINUX_ADAPTER=$(CDPATH= cd -P "$SCRIPT_DIR/../../linux/environments" && pwd)/python-3.12.sh
[ -x "$LINUX_ADAPTER" ] || fail "Shared Ubuntu Linux Python 3.12 adapter is missing or not executable: $LINUX_ADAPTER"

DEVKIT_WULF_ALLOW_WSL=1 DEVKIT_WULF_REQUIRE_WSL=1 exec "$LINUX_ADAPTER" "${1:-plan}"

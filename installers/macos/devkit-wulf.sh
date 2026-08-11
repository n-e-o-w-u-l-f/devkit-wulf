#!/bin/sh
set -eu

fail() {
    printf '%s\n' "[devkit-wulf] $*" >&2
    exit 2
}

[ "$(uname -s 2>/dev/null || printf unknown)" = "Darwin" ] || fail "This entrypoint is for macOS only."

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -P "$SCRIPT_DIR/../.." && pwd)

if [ "${2:-}" = "python@3.12" ]; then
    case "${1:-}" in
        plan|install|verify)
            action=$1
            shift 2
            adapter="$SCRIPT_DIR/environments/python-3.12.sh"
            [ -x "$adapter" ] || fail "Python 3.12 macOS adapter is missing or not executable: $adapter"
            exec "$adapter" "$action" "$@"
            ;;
        *)
            fail "python@3.12 supports only plan, install and verify."
            ;;
    esac
fi

CORE="$ROOT_DIR/bin/devkit-wulf"
[ -f "$CORE" ] || fail "POSIX orchestrator core not found: $CORE"
[ -x "$CORE" ] || fail "POSIX orchestrator core is not executable: $CORE"
exec "$CORE" "$@"

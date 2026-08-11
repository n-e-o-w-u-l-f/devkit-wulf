#!/bin/sh
set -eu

fail() {
    printf '%s\n' "[devkit-wulf] $*" >&2
    exit 2
}

[ "$(uname -s 2>/dev/null || printf unknown)" = "Linux" ] || fail "This entrypoint must run inside a WSL Linux distribution."

is_wsl=0
for marker in /proc/sys/kernel/osrelease /proc/version; do
    if [ -r "$marker" ] && grep -Eiq '(microsoft|wsl)' "$marker"; then
        is_wsl=1
        break
    fi
done
[ "$is_wsl" -eq 1 ] || fail "WSL was not detected. Use installers/linux/devkit-wulf.sh on native Linux."

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -P "$SCRIPT_DIR/../.." && pwd)

if [ "${2:-}" = "python@3.12" ]; then
    case "${1:-}" in
        plan|install|verify)
            action=$1
            shift 2
            adapter="$SCRIPT_DIR/environments/python-3.12.sh"
            [ -x "$adapter" ] || fail "Python 3.12 WSL adapter is missing or not executable: $adapter"
            exec "$adapter" "$action" "$@"
            ;;
        *) fail "python@3.12 supports only plan, install and verify." ;;
    esac
fi

if [ "${2:-}" = "go@stable" ]; then
    case "${1:-}" in
        plan|install|verify)
            action=$1
            shift 2
            adapter="$SCRIPT_DIR/environments/go-stable.sh"
            [ -x "$adapter" ] || fail "Go stable WSL adapter is missing or not executable: $adapter"
            exec "$adapter" "$action" "$@"
            ;;
        *) fail "go@stable supports only plan, install and verify." ;;
    esac
fi

if [ "${2:-}" = "rust@stable" ]; then
    case "${1:-}" in
        plan|install|verify)
            action=$1
            shift 2
            adapter="$SCRIPT_DIR/environments/rust-stable.sh"
            [ -x "$adapter" ] || fail "Rust stable WSL adapter is missing or not executable: $adapter"
            exec "$adapter" "$action" "$@"
            ;;
        *) fail "rust@stable supports only plan, install and verify." ;;
    esac
fi

CORE="$ROOT_DIR/bin/devkit-wulf"
[ -f "$CORE" ] || fail "POSIX orchestrator core not found: $CORE"
[ -x "$CORE" ] || fail "POSIX orchestrator core is not executable: $CORE"
exec "$CORE" "$@"

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

route_selector() {
    selector=$1
    adapter_name=$2
    shift 2
    if [ "${2:-}" = "$selector" ]; then
        case "${1:-}" in
            plan|install|verify)
                action=$1
                shift 2
                adapter="$SCRIPT_DIR/environments/$adapter_name"
                [ -x "$adapter" ] || fail "$selector Linux adapter is missing or not executable: $adapter"
                exec "$adapter" "$action" "$@"
                ;;
            *) fail "$selector supports only plan, install and verify." ;;
        esac
    fi
}

route_selector 'python@3.12' 'python-3.12.sh' "$@"
route_selector 'go@stable' 'go-stable.sh' "$@"
route_selector 'rust@stable' 'rust-stable.sh' "$@"
route_selector 'flutter@stable' 'flutter-stable.sh' "$@"

CORE="$ROOT_DIR/bin/devkit-wulf"
[ -f "$CORE" ] || fail "POSIX orchestrator core not found: $CORE"
[ -x "$CORE" ] || fail "POSIX orchestrator core is not executable: $CORE"
exec "$CORE" "$@"

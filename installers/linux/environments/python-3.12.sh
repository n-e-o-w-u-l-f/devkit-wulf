#!/bin/sh
set -eu

fail() {
    printf '%s\n' "[devkit-wulf][python-3.12] $*" >&2
    exit 2
}

[ "$(uname -s 2>/dev/null || printf unknown)" = "Linux" ] || fail "This adapter requires Linux."

is_wsl=0
for marker in /proc/sys/kernel/osrelease /proc/version; do
    if [ -r "$marker" ] && grep -Eiq '(microsoft|wsl)' "$marker"; then
        is_wsl=1
        break
    fi
done
if [ "$is_wsl" -eq 1 ] && [ "${DEVKIT_WULF_ALLOW_WSL:-0}" != "1" ]; then
    fail "WSL detected. Use installers/wsl/environments/python-3.12.sh."
fi
if [ "$is_wsl" -eq 0 ] && [ "${DEVKIT_WULF_REQUIRE_WSL:-0}" = "1" ]; then
    fail "WSL was required but not detected."
fi

[ -r /etc/os-release ] || fail "/etc/os-release is required for exact distro gating."
# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] || fail "Only Ubuntu 24.04 is enabled for the native APT Python 3.12 adapter."
[ "${VERSION_ID:-}" = "24.04" ] || fail "Only Ubuntu 24.04 is enabled for the native APT Python 3.12 adapter."

command -v apt-get >/dev/null 2>&1 || fail "apt-get is required."
command -v dpkg-query >/dev/null 2>&1 || fail "dpkg-query is required."

ACTION=${1:-plan}
case "$ACTION" in
    plan|install|verify) ;;
    *) fail "Usage: $0 [plan|install|verify]" ;;
esac

run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        fail "This APT mutation requires root or sudo for the narrow package-manager commands."
    fi
}

python312_version() {
    python3.12 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])'
}

cleanup_smoke_dir() {
    _dw_py_tmp=${1:-}
    [ -n "$_dw_py_tmp" ] || return 0
    case "$_dw_py_tmp" in
        "${TMPDIR:-/tmp}"/devkit-wulf-python312.*) rm -rf "$_dw_py_tmp" ;;
        *) fail "Refusing unsafe temporary cleanup path: $_dw_py_tmp" ;;
    esac
}

verify_python312() {
    command -v python3.12 >/dev/null 2>&1 || fail "python3.12 is not installed."
    for package in python3.12 python3.12-venv; do
        status=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)
        [ "$status" = "installed" ] || fail "Required Ubuntu package is not installed: $package"
    done

    version=$(python312_version)
    case "$version" in
        3.12.*) ;;
        *) fail "Resolved runtime is not Python 3.12: $version" ;;
    esac

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-python312.XXXXXX") || fail "Unable to create venv smoke directory."
    trap 'cleanup_smoke_dir "$tmp"' EXIT HUP INT TERM
    python3.12 -m venv "$tmp" || fail "venv smoke test failed."
    "$tmp/bin/python" -m pip --version >/dev/null || fail "pip smoke test inside venv failed."
    cleanup_smoke_dir "$tmp"
    trap - EXIT HUP INT TERM
    tmp=''

    printf '%s\n' "python_executable=$(command -v python3.12)"
    printf '%s\n' "python_version=$version"
}

case "$ACTION" in
    plan)
        printf '%s\n' 'environment=python'
        printf '%s\n' 'version_family=3.12'
        printf '%s\n' 'platform=ubuntu'
        printf '%s\n' 'version_id=24.04'
        printf '%s\n' "domain=$( [ "$is_wsl" -eq 1 ] && printf wsl2 || printf native )"
        printf '%s\n' 'strategy=apt'
        printf '%s\n' 'packages=python3.12 python3.12-venv'
        printf '%s\n' 'version_policy=distribution-security-backports'
        printf '%s\n' 'system_python_replacement=false'
        printf '%s\n' 'global_pip_install=false'
        apt-cache policy python3.12 python3.12-venv 2>/dev/null || true
        ;;
    verify)
        verify_python312
        ;;
    install)
        if command -v python3.12 >/dev/null 2>&1 \
            && dpkg-query -W -f='${db:Status-Status}' python3.12 2>/dev/null | grep -qx installed \
            && dpkg-query -W -f='${db:Status-Status}' python3.12-venv 2>/dev/null | grep -qx installed; then
            verify_python312
            printf '%s\n' 'result=already-satisfied'
            exit 0
        fi

        run_privileged apt-get update
        if [ "$(id -u)" -eq 0 ]; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3.12 python3.12-venv
        else
            sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3.12 python3.12-venv
        fi
        verify_python312
        printf '%s\n' 'result=installed'
        ;;
esac

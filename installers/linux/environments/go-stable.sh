#!/bin/sh
set -eu

fail() {
    printf '%s\n' "[devkit-wulf][go@stable] $*" >&2
    exit 2
}

die() { fail "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

[ "$(uname -s 2>/dev/null || printf unknown)" = "Linux" ] || fail "This adapter requires Linux."

is_wsl=0
for marker in /proc/sys/kernel/osrelease /proc/version; do
    if [ -r "$marker" ] && grep -Eiq '(microsoft|wsl)' "$marker"; then
        is_wsl=1
        break
    fi
done
if [ "$is_wsl" -eq 1 ] && [ "${DEVKIT_WULF_ALLOW_WSL:-0}" != "1" ]; then
    fail "WSL detected. Use installers/wsl/environments/go-stable.sh."
fi
if [ "$is_wsl" -eq 0 ] && [ "${DEVKIT_WULF_REQUIRE_WSL:-0}" = "1" ]; then
    fail "WSL was required but not detected."
fi

ACTION=${1:-plan}
EXPERIMENTAL=0
case "$ACTION" in
    plan|install|verify) ;;
    *) fail "Usage: $0 [plan|install|verify] [--experimental]" ;;
esac
case "${2:-}" in
    '') ;;
    --experimental) EXPERIMENTAL=1 ;;
    *) fail "Unknown option: ${2:-}" ;;
esac
[ "${3:-}" = '' ] || fail "Too many arguments."
if [ "$ACTION" = install ] && [ "$EXPERIMENTAL" -ne 1 ]; then
    fail "go@stable remains experimental; install requires --experimental."
fi

case "$(uname -m 2>/dev/null || printf unknown)" in
    x86_64|amd64) ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    riscv64) ARCH=riscv64 ;;
    ppc64le) ARCH=ppc64le ;;
    s390x) ARCH=s390x ;;
    *) fail "No verified Go stable Linux artifact is mapped for this architecture." ;;
esac

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -P "$SCRIPT_DIR/../../.." && pwd)
GO_ARTIFACT_MANIFEST="$ROOT_DIR/manifests/go-artifact.json"
[ -f "$GO_ARTIFACT_MANIFEST" ] || fail "Go artifact manifest not found: $GO_ARTIFACT_MANIFEST"
export GO_ARTIFACT_MANIFEST

STATE_DIR=${DEVKIT_WULF_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/devkit-wulf}
case "$STATE_DIR" in /*) ;; *) fail "Go state directory must be absolute: $STATE_DIR" ;; esac
export STATE_DIR

command -v jq >/dev/null 2>&1 || fail "jq is required by the verified Go artifact contract."
command -v tar >/dev/null 2>&1 || fail "tar is required by the verified Go artifact contract."

sha256_file() {
    file=$1
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        printf unavailable
    fi
}

download_https() {
    url=$1
    destination=$2
    case "$url" in https://*) ;; *) fail "GATE-04 blocked non-HTTPS Go source: $url" ;; esac
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 --output "$destination" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget --https-only --secure-protocol=TLSv1_2 -q -O "$destination" "$url"
    else
        fail "curl or wget is required to download verified Go artifacts."
    fi
}

# shellcheck source=../../../lib/go-artifact.sh
. "$ROOT_DIR/lib/go-artifact.sh"

case "$ACTION" in
    plan)
        printf '%s\n' 'environment=go'
        printf '%s\n' 'selector=go@stable'
        printf '%s\n' "platform=linux"
        printf '%s\n' "domain=$( [ "$is_wsl" -eq 1 ] && printf wsl2 || printf native )"
        printf '%s\n' "architecture=$ARCH"
        printf '%s\n' 'strategy=verified-artifact-helper'
        plan_go_artifact linux "$ARCH" || fail "Unable to plan verified Go stable artifact."
        ;;
    verify)
        verify_go_artifact linux "$ARCH" || fail "Managed Go stable artifact verification failed."
        printf '%s\n' 'result=verified'
        ;;
    install)
        install_go_artifact linux "$ARCH"
        verify_go_artifact linux "$ARCH" || fail "Go installation completed but managed verification failed."
        printf '%s\n' 'result=installed-or-already-satisfied'
        ;;
esac

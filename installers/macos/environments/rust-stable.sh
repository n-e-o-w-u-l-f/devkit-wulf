#!/bin/sh
set -eu

fail() {
    printf '%s\n' "[devkit-wulf][rust@stable] $*" >&2
    exit 2
}

die() { fail "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

[ "$(uname -s 2>/dev/null || printf unknown)" = "Darwin" ] || fail "This adapter is for macOS only."

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
    fail "rust@stable remains experimental; install requires --experimental."
fi

case "$(uname -m 2>/dev/null || printf unknown)" in
    x86_64|amd64) ARCH=amd64 ;;
    arm64|aarch64) ARCH=arm64 ;;
    *) fail "No verified Rust stable macOS rustup-init artifact is mapped for this architecture." ;;
esac

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -P "$SCRIPT_DIR/../../.." && pwd)
RUSTUP_ARTIFACT_MANIFEST="$ROOT_DIR/manifests/rustup-artifact.json"
[ -f "$RUSTUP_ARTIFACT_MANIFEST" ] || fail "Rustup artifact manifest not found: $RUSTUP_ARTIFACT_MANIFEST"
export RUSTUP_ARTIFACT_MANIFEST

STATE_DIR=${DEVKIT_WULF_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/devkit-wulf}
case "$STATE_DIR" in /*) ;; *) fail "Rustup state directory must be absolute: $STATE_DIR" ;; esac
export STATE_DIR

command -v jq >/dev/null 2>&1 || fail "jq is required by the verified rustup artifact contract."

sha256_file() {
    file=$1
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    else
        printf unavailable
    fi
}

download_https() {
    url=$1
    destination=$2
    case "$url" in https://*) ;; *) fail "GATE-04 blocked non-HTTPS Rust source: $url" ;; esac
    command -v curl >/dev/null 2>&1 || fail "curl is required to download verified rustup-init on macOS."
    curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 --output "$destination" "$url"
}

# shellcheck source=../../../lib/rustup-artifact.sh
. "$ROOT_DIR/lib/rustup-artifact.sh"

case "$ACTION" in
    plan)
        printf '%s\n' 'environment=rust'
        printf '%s\n' 'selector=rust@stable'
        printf '%s\n' 'platform=macos'
        printf '%s\n' 'domain=native'
        printf '%s\n' "architecture=$ARCH"
        printf '%s\n' 'strategy=verified-rustup-init'
        plan_rustup_artifact macos "$ARCH" || fail "Unable to plan verified Rust stable artifact."
        ;;
    verify)
        verify_rustup_artifact macos "$ARCH" || fail "Managed Rust stable artifact verification failed."
        printf '%s\n' 'result=verified'
        ;;
    install)
        install_rustup_artifact macos "$ARCH"
        verify_rustup_artifact macos "$ARCH" || fail "Rust installation completed but managed verification failed."
        printf '%s\n' 'result=installed-or-already-satisfied'
        ;;
esac

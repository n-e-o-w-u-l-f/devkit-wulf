#!/bin/sh
set -eu

fail() {
    printf '%s\n' "[devkit-wulf][rust@stable] $*" >&2
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
    fail "WSL detected. Use installers/wsl/environments/rust-stable.sh."
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
    fail "rust@stable remains experimental; install requires --experimental."
fi

case "$(uname -m 2>/dev/null || printf unknown)" in
    x86_64|amd64) ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) fail "No verified Rust stable Linux rustup-init artifact is mapped for this architecture." ;;
esac

command -v getconf >/dev/null 2>&1 || fail "getconf is required to prove the verified Linux glibc target."
getconf GNU_LIBC_VERSION >/dev/null 2>&1 || fail "The current verified rust@stable Linux contract is glibc-only; musl and other libc families require a separate target contract."

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
    case "$url" in https://*) ;; *) fail "GATE-04 blocked non-HTTPS Rust source: $url" ;; esac
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 --output "$destination" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget --https-only --secure-protocol=TLSv1_2 -q -O "$destination" "$url"
    else
        fail "curl or wget is required to download the verified rustup-init artifact."
    fi
}

# shellcheck source=../../../lib/rustup-artifact.sh
. "$ROOT_DIR/lib/rustup-artifact.sh"

case "$ACTION" in
    plan)
        printf '%s\n' 'environment=rust'
        printf '%s\n' 'selector=rust@stable'
        printf '%s\n' 'platform=linux'
        printf '%s\n' "domain=$( [ "$is_wsl" -eq 1 ] && printf wsl2 || printf native )"
        printf '%s\n' "architecture=$ARCH"
        printf '%s\n' 'strategy=verified-rustup-init'
        plan_rustup_artifact linux "$ARCH" || fail "Unable to plan verified Rust stable artifact."
        ;;
    verify)
        verify_rustup_artifact linux "$ARCH" || fail "Managed Rust stable artifact verification failed."
        printf '%s\n' 'result=verified'
        ;;
    install)
        install_rustup_artifact linux "$ARCH"
        verify_rustup_artifact linux "$ARCH" || fail "Rust installation completed but managed verification failed."
        printf '%s\n' 'result=installed-or-already-satisfied'
        ;;
esac

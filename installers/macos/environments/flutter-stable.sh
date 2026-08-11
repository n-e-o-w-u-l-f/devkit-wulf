#!/bin/sh
set -eu

fail() { printf '%s\n' "[devkit-wulf][flutter@stable] $*" >&2; exit 2; }
die() { fail "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
log() { printf '%s\n' "[devkit-wulf][flutter@stable] $*" >&2; }
warn() { printf '%s\n' "[devkit-wulf][flutter@stable][warning] $*" >&2; }
privileged() { fail "Flutter stable archive installation must remain unprivileged."; }

[ "$(uname -s 2>/dev/null || printf unknown)" = Darwin ] || fail "This adapter is for macOS only."

ACTION=${1:-plan}
EXPERIMENTAL=0
case "$ACTION" in plan|install|verify) ;; *) fail "Usage: $0 [plan|install|verify] [--experimental]" ;; esac
case "${2:-}" in '') ;; --experimental) EXPERIMENTAL=1 ;; *) fail "Unknown option: ${2:-}" ;; esac
[ "${3:-}" = '' ] || fail "Too many arguments."
[ "$ACTION" != install ] || [ "$EXPERIMENTAL" -eq 1 ] || fail "flutter@stable remains experimental; install requires --experimental."

case "$(uname -m 2>/dev/null || printf unknown)" in
  x86_64|amd64) ARCH=amd64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) fail "No reviewed Flutter stable macOS archive is mapped for this architecture." ;;
esac

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -P "$SCRIPT_DIR/../../.." && pwd)
ARTIFACT_MANIFEST="$ROOT_DIR/manifests/artifacts.json"
STATE_DIR=${DEVKIT_WULF_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/devkit-wulf}
export ARTIFACT_MANIFEST STATE_DIR
case "$STATE_DIR" in /*) ;; *) fail "Flutter state directory must be absolute: $STATE_DIR" ;; esac

have jq || fail "jq is required by the reviewed Flutter artifact contract."
have unzip || fail "unzip is required by the reviewed Flutter macOS artifact contract."

sha256_file() {
  if have shasum; then shasum -a 256 "$1" | awk '{print $1}'
  elif have sha256sum; then sha256sum "$1" | awk '{print $1}'
  else printf unavailable
  fi
}

download_https() {
  url=$1; destination=$2
  case "$url" in https://*) ;; *) fail "GATE-04 blocked non-HTTPS Flutter source: $url" ;; esac
  have curl || fail "curl is required to download verified Flutter artifacts on macOS."
  curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 --output "$destination" "$url"
}

# shellcheck source=../../../lib/artifacts.sh
. "$ROOT_DIR/lib/artifacts.sh"
# shellcheck source=../../../lib/flutter-posix-environment.sh
. "$ROOT_DIR/lib/flutter-posix-environment.sh"

case "$ACTION" in
  plan)
    printf '%s\n' 'environment=flutter' 'selector=flutter@stable' 'platform=macos' 'domain=native' "architecture=$ARCH" 'strategy=verified-posix-artifact'
    plan_verified_artifact flutter macos macos "$ARCH" || fail "Unable to plan verified Flutter stable artifact."
    ;;
  verify)
    verify_flutter_stable_managed || fail "Managed Flutter stable verification failed."
    printf '%s\n' 'result=verified'
    ;;
  install)
    install_flutter_stable_managed macos macos "$ARCH"
    printf '%s\n' 'result=installed-or-already-satisfied'
    ;;
esac

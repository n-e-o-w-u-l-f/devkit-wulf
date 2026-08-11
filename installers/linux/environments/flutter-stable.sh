#!/bin/sh
set -eu

fail() { printf '%s\n' "[devkit-wulf][flutter@stable] $*" >&2; exit 2; }
die() { fail "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
log() { printf '%s\n' "[devkit-wulf][flutter@stable] $*" >&2; }
warn() { printf '%s\n' "[devkit-wulf][flutter@stable][warning] $*" >&2; }
privileged() { fail "Flutter stable archive installation must remain unprivileged."; }

[ "$(uname -s 2>/dev/null || printf unknown)" = Linux ] || fail "This adapter requires native Linux."
for marker in /proc/sys/kernel/osrelease /proc/version; do
  if [ -r "$marker" ] && grep -Eiq '(microsoft|wsl)' "$marker"; then
    fail "WSL is not enabled for flutter@stable; use a separately reviewed WSL contract when available."
  fi
done

ACTION=${1:-plan}
EXPERIMENTAL=0
case "$ACTION" in plan|install|verify) ;; *) fail "Usage: $0 [plan|install|verify] [--experimental]" ;; esac
case "${2:-}" in '') ;; --experimental) EXPERIMENTAL=1 ;; *) fail "Unknown option: ${2:-}" ;; esac
[ "${3:-}" = '' ] || fail "Too many arguments."
[ "$ACTION" != install ] || [ "$EXPERIMENTAL" -eq 1 ] || fail "flutter@stable remains experimental; install requires --experimental."

case "$(uname -m 2>/dev/null || printf unknown)" in
  x86_64|amd64) ARCH=amd64 ;;
  *) fail "The reviewed Flutter Linux archive contract currently supports amd64 only." ;;
esac

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -P "$SCRIPT_DIR/../../.." && pwd)
ARTIFACT_MANIFEST="$ROOT_DIR/manifests/artifacts.json"
STATE_DIR=${DEVKIT_WULF_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/devkit-wulf}
export ARTIFACT_MANIFEST STATE_DIR
case "$STATE_DIR" in /*) ;; *) fail "Flutter state directory must be absolute: $STATE_DIR" ;; esac

have jq || fail "jq is required by the reviewed Flutter artifact contract."
have tar || fail "tar is required by the reviewed Flutter Linux artifact contract."

sha256_file() {
  if have sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif have shasum; then shasum -a 256 "$1" | awk '{print $1}'
  else printf unavailable
  fi
}

download_https() {
  url=$1; destination=$2
  case "$url" in https://*) ;; *) fail "GATE-04 blocked non-HTTPS Flutter source: $url" ;; esac
  if have curl; then curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 --output "$destination" "$url"
  elif have wget; then wget --https-only --secure-protocol=TLSv1_2 -q -O "$destination" "$url"
  else fail "curl or wget is required to download verified Flutter artifacts."
  fi
}

# shellcheck source=../../../lib/artifacts.sh
. "$ROOT_DIR/lib/artifacts.sh"
# shellcheck source=../../../lib/flutter-posix-environment.sh
. "$ROOT_DIR/lib/flutter-posix-environment.sh"

case "$ACTION" in
  plan)
    printf '%s\n' 'environment=flutter' 'selector=flutter@stable' 'platform=linux' 'domain=native' "architecture=$ARCH" 'strategy=verified-posix-artifact'
    plan_verified_artifact flutter linux linux "$ARCH" || fail "Unable to plan verified Flutter stable artifact."
    ;;
  verify)
    verify_flutter_stable_managed linux || fail "Managed Flutter stable verification failed."
    printf '%s\n' 'result=verified'
    ;;
  install)
    install_flutter_stable_managed linux linux "$ARCH"
    printf '%s\n' 'result=installed-or-already-satisfied'
    ;;
esac

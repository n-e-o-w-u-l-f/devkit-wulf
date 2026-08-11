#!/bin/sh
set -eu

fail() {
  printf '%s\n' "[devkit-wulf][kubectl@stable] $*" >&2
  exit 2
}

[ "$(uname -s 2>/dev/null || printf unknown)" = Darwin ] || fail "This adapter is for macOS only."

ACTION=${1:-plan}
EXPERIMENTAL=0
case "$ACTION" in plan|install|verify) ;; *) fail "Usage: $0 [plan|install|verify] [--experimental]" ;; esac
case "${2:-}" in '') ;; --experimental) EXPERIMENTAL=1 ;; *) fail "Unknown option: ${2:-}" ;; esac
[ "${3:-}" = '' ] || fail "Too many arguments."
if [ "$ACTION" = install ] && [ "$EXPERIMENTAL" -ne 1 ]; then
  fail "kubectl@stable remains experimental; install requires --experimental."
fi

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -P "$SCRIPT_DIR/../../.." && pwd)
KUBECTL_NATIVE_MANIFEST="$ROOT_DIR/manifests/kubectl-native.json"
export KUBECTL_NATIVE_MANIFEST
[ -f "$KUBECTL_NATIVE_MANIFEST" ] || fail "kubectl native manifest not found: $KUBECTL_NATIVE_MANIFEST"
command -v jq >/dev/null 2>&1 || fail "jq is required by the native macOS kubectl contract."

# shellcheck source=../../../lib/kubectl-macos.sh
. "$ROOT_DIR/lib/kubectl-macos.sh"
ARCH=$(kubectl_macos_architecture) || fail "No reviewed macOS kubectl artifact is mapped for this architecture."

case "$ACTION" in
  plan)
    plan_kubectl_macos "$ARCH" || fail "Unable to plan native macOS kubectl artifact."
    ;;
  verify)
    verify_kubectl_macos_managed "$ARCH" || fail "Managed macOS kubectl verification failed."
    printf '%s\n' 'result=verified'
    ;;
  install)
    install_kubectl_macos "$ARCH" || fail "Native macOS kubectl installation failed."
    ;;
esac

#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-kubectl-macos.XXXXXX")
cleanup_fixture() {
  case "$TMP_ROOT" in
    "${TMPDIR:-/tmp}"/devkit-wulf-kubectl-macos.*)
      [ ! -L "$TMP_ROOT" ] || return 1
      [ ! -e "$TMP_ROOT" ] || rm -r "$TMP_ROOT"
      ;;
    *) return 1 ;;
  esac
}
trap cleanup_fixture 0 1 2 15

HOME="$TMP_ROOT/home with spaces"
export HOME
KUBECTL_NATIVE_MANIFEST="$ROOT_DIR/manifests/kubectl-native.json"
export KUBECTL_NATIVE_MANIFEST
mkdir -p "$HOME"

fail() { printf '%s\n' "fixture failure: $*" >&2; exit 1; }

# shellcheck source=../lib/kubectl-macos.sh
. "$ROOT_DIR/lib/kubectl-macos.sh"

ARCH=$(kubectl_macos_architecture) || fail "runner architecture is not mapped"
VERSION=v9.9.9
VERSION_FILE="$TMP_ROOT/stable.txt"
FAKE_BINARY="$TMP_ROOT/kubectl"
CHECKSUM_FILE="$TMP_ROOT/kubectl.sha256"
printf '%s' "$VERSION" > "$VERSION_FILE"
cat > "$FAKE_BINARY" <<'EOF'
#!/bin/sh
if [ "$#" -eq 3 ] && [ "$1" = version ] && [ "$2" = --client=true ] && [ "$3" = --output=json ]; then
  printf '%s\n' '{"clientVersion":{"gitVersion":"v9.9.9"}}'
  exit 0
fi
exit 2
EOF
chmod 0755 "$FAKE_BINARY"
SHA=$(kubectl_macos_sha256 "$FAKE_BINARY") || fail "unable to hash fake kubectl"
printf '%s  kubectl\n' "$SHA" > "$CHECKSUM_FILE"

kubectl_macos_download() {
  url=$1
  destination=$2
  case "$url" in
    'https://dl.k8s.io/release/stable.txt') cp "$VERSION_FILE" "$destination" ;;
    "https://dl.k8s.io/release/$VERSION/bin/darwin/$ARCH/kubectl") cp "$FAKE_BINARY" "$destination" ;;
    "https://dl.k8s.io/release/$VERSION/bin/darwin/$ARCH/kubectl.sha256") cp "$CHECKSUM_FILE" "$destination" ;;
    *) fail "fixture blocked unexpected URL: $url" ;;
  esac
}

PATHS=$(kubectl_macos_paths) || fail "unable to resolve managed paths"
BIN_DIR=$(printf '%s\n' "$PATHS" | sed -n '2p')
BINARY=$(printf '%s\n' "$PATHS" | sed -n '3p')
PATH="$BIN_DIR:$PATH"
export PATH

ARTIFACT=$(kubectl_macos_artifact "$ARCH") || fail "unable to resolve artifact"
[ "$(printf '%s\n' "$ARTIFACT" | sed -n '1p')" = "$VERSION" ] || fail "stable version mismatch"
[ "$(kubectl_macos_expected_sha256 "https://dl.k8s.io/release/$VERSION/bin/darwin/$ARCH/kubectl.sha256")" = "$SHA" ] || fail "checksum mismatch"

PLAN=$(plan_kubectl_macos "$ARCH") || fail "plan failed"
printf '%s\n' "$PLAN" | grep -F 'mutates_host=false' >/dev/null || fail "plan did not declare non-mutation"
[ ! -e "$BINARY" ] || fail "plan unexpectedly mutated destination"

RESULT=$(install_kubectl_macos "$ARCH") || fail "first install failed"
printf '%s\n' "$RESULT" | grep -F 'result=installed' >/dev/null || fail "first install result mismatch"
verify_kubectl_macos_managed "$ARCH" || fail "installed fixture did not verify"

kubectl_macos_download() { fail 'second install must be fully offline'; }
SECOND=$(install_kubectl_macos "$ARCH") || fail "second install failed"
printf '%s\n' "$SECOND" | grep -F 'result=already-satisfied' >/dev/null || fail "second install was not offline-idempotent"

printf '%s\n' '# tamper' >> "$BINARY"
if verify_kubectl_macos_managed "$ARCH"; then fail "tampered kubectl incorrectly verified"; fi

HOME="$TMP_ROOT/foreign home"
export HOME
mkdir -p "$HOME/.local/share/devkit-wulf/kubectl/bin"
FOREIGN_PATHS=$(kubectl_macos_paths) || fail "unable to resolve foreign paths"
FOREIGN_BIN=$(printf '%s\n' "$FOREIGN_PATHS" | sed -n '2p')
FOREIGN_BINARY=$(printf '%s\n' "$FOREIGN_PATHS" | sed -n '3p')
printf '%s\n' foreign > "$FOREIGN_BINARY"
chmod 0755 "$FOREIGN_BINARY"
PATH="$FOREIGN_BIN:$PATH"
export PATH
kubectl_macos_download() { fail 'foreign conflict must be detected before network'; }
if install_kubectl_macos "$ARCH" >"$TMP_ROOT/foreign.out" 2>&1; then
  fail "foreign destination unexpectedly accepted"
fi
grep -F 'GATE-08 existing kubectl selector destination' "$TMP_ROOT/foreign.out" >/dev/null || fail "foreign conflict did not fail at GATE-08"

printf '%s\n' 'macOS kubectl offline artifact fixture: OK'

#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-go-test.XXXXXX")
HOME="$TEST_ROOT/home with space"
STATE_DIR="$TEST_ROOT/state"
GO_ARTIFACT_MANIFEST="$ROOT/manifests/go-artifact.json"
INDEX_FIXTURE="$TEST_ROOT/index.json"
DOWNLOAD_LOG="$TEST_ROOT/downloads.log"
export HOME STATE_DIR GO_ARTIFACT_MANIFEST
cleanup() { find "$TEST_ROOT" -type l -delete 2>/dev/null || true; find "$TEST_ROOT" -type f -delete 2>/dev/null || true; find "$TEST_ROOT" -depth -type d -exec rmdir {} \; 2>/dev/null || true; }
trap 'cleanup' EXIT HUP INT TERM

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }
mkdir -p "$HOME/.local/share" "$STATE_DIR"
DEST="$HOME/.local/share/devkit-wulf/go"
PATH_DIR="$DEST/bin"
PATH="$PATH_DIR:$PATH"
export PATH

FIXTURE="$TEST_ROOT/fixture"
mkdir -p "$FIXTURE/go/bin"
cat > "$FIXTURE/go/bin/go" <<'EOF'
#!/bin/sh
case "${1:-}" in
  version) printf 'go version go1.25.1 linux/amd64\n' ;;
  env) printf 'linux\namd64\n' ;;
  *) printf 'fixture go\n' ;;
esac
EOF
cat > "$FIXTURE/go/bin/gofmt" <<'EOF'
#!/bin/sh
printf 'fixture gofmt\n'
EOF
chmod 0755 "$FIXTURE/go/bin/go" "$FIXTURE/go/bin/gofmt"
ARCHIVE="$TEST_ROOT/go1.25.1.linux-amd64.tar.gz"
tar -czf "$ARCHIVE" -C "$FIXTURE" go

have() { command -v "$1" >/dev/null 2>&1; }
die() { printf '%s\n' "$*" >&2; exit 1; }
sha256_file() {
  file=$1
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$file" | awk '{print $1}'
  else printf unavailable
  fi
}
ARCHIVE_SHA=$(sha256_file "$ARCHIVE")
[ "$ARCHIVE_SHA" != unavailable ] || { echo "SHA-256 implementation required" >&2; exit 1; }

write_index() {
  sha=$1
  cat > "$INDEX_FIXTURE" <<EOF
[
  {"version":"go1.26rc1","stable":false,"files":[]},
  {"version":"go1.25.1","stable":true,"files":[
    {"filename":"go1.25.1.linux-amd64.tar.gz","os":"linux","arch":"amd64","version":"go1.25.1","sha256":"$sha","size":123,"kind":"archive"},
    {"filename":"go1.25.1.darwin-arm64.tar.gz","os":"darwin","arch":"arm64","version":"go1.25.1","sha256":"1111111111111111111111111111111111111111111111111111111111111111","size":123,"kind":"archive"}
  ]},
  {"version":"go1.24.9","stable":true,"files":[]}
]
EOF
}
write_index "$ARCHIVE_SHA"
: > "$DOWNLOAD_LOG"
CURRENT_ARCHIVE=$ARCHIVE
download_https() {
  url=$1 dest=$2
  printf '%s\n' "$url" >> "$DOWNLOAD_LOG"
  case "$url" in
    'https://go.dev/dl/?mode=json') cp "$INDEX_FIXTURE" "$dest" ;;
    'https://go.dev/dl/go1.25.1.linux-amd64.tar.gz') cp "$CURRENT_ARCHIVE" "$dest" ;;
    *) echo "unexpected fixture URL: $url" >&2; return 97 ;;
  esac
}

# shellcheck source=../lib/go-artifact.sh
. "$ROOT/lib/go-artifact.sh"

[ "$(go_artifact_target_json linux amd64 | jq -r '.go_os')" = linux ]
[ "$(go_artifact_target_json macos arm64 | jq -r '.go_os')" = darwin ]
if go_artifact_target_json macos riscv64 | grep -q .; then echo "unmapped Go architecture unexpectedly resolved" >&2; exit 1; fi

# Sourced helper must not overwrite common caller variables.
platform=caller-platform
arch=caller-arch
source=caller-source
plan=$(plan_go_artifact linux amd64)
[ "$platform" = caller-platform ] && [ "$arch" = caller-arch ] && [ "$source" = caller-source ]
printf '%s\n' "$plan" | grep 'version: go1.25.1' >/dev/null
printf '%s\n' "$plan" | grep 'integrity: sha256-release-index' >/dev/null
printf '%s\n' "$plan" | grep 'path_mutation: none' >/dev/null
printf '%s\n' "$plan" | grep 'privilege: none' >/dev/null
printf '%s\n' "$plan" | grep 'mutates_host: false' >/dev/null
[ ! -e "$DEST" ]

: > "$DOWNLOAD_LOG"
install_go_artifact linux amd64
verify_go_artifact linux amd64
[ -f "$DEST/.devkit-wulf-go.json" ]
[ -x "$DEST/bin/go" ] && [ -x "$DEST/bin/gofmt" ]
[ "$(sed -n '1p' "$STATE_DIR/go-artifact.jsonl" | jq -r '.action')" = mutation-intent ]
[ "$(tail -n 1 "$STATE_DIR/go-artifact.jsonl" | jq -r '.action')" = installed-verified ]

# Exact managed second install is fully offline.
: > "$DOWNLOAD_LOG"
install_go_artifact linux amd64
[ ! -s "$DOWNLOAD_LOG" ]
[ "$(tail -n 1 "$STATE_DIR/go-artifact.jsonl" | jq -r '.action')" = observed-managed ]

# Tampering invalidates marker-bound verification.
printf '\n# tampered\n' >> "$DEST/bin/go"
if verify_go_artifact linux amd64; then echo "tampered Go binary unexpectedly verified" >&2; exit 1; fi
find "$DEST" -type f -delete
find "$DEST" -depth -type d -exec rmdir {} \;

# Foreign destination is refused before network access.
mkdir -p "$DEST"
: > "$DOWNLOAD_LOG"
if install_go_artifact linux amd64 >/dev/null 2>&1; then echo "foreign Go destination unexpectedly adopted" >&2; exit 1; fi
[ ! -s "$DOWNLOAD_LOG" ]
rmdir "$DEST"

# Missing PATH declaration is refused before network access.
OLD_PATH=$PATH
PATH=$(printf '%s' "$PATH" | awk -v RS=: -v ORS=: -v x="$PATH_DIR" '$0 != x {print}' | sed 's/:$//')
export PATH
: > "$DOWNLOAD_LOG"
if install_go_artifact linux amd64 >/dev/null 2>&1; then echo "missing Go PATH declaration unexpectedly accepted" >&2; exit 1; fi
[ ! -s "$DOWNLOAD_LOG" ]
PATH=$OLD_PATH
export PATH

# Checksum mismatch fails before destination placement.
write_index '0000000000000000000000000000000000000000000000000000000000000000'
: > "$DOWNLOAD_LOG"
if install_go_artifact linux amd64 >/dev/null 2>&1; then echo "Go checksum mismatch unexpectedly accepted" >&2; exit 1; fi
[ ! -e "$DEST" ]
write_index "$ARCHIVE_SHA"

# Archive containing a symlink is rejected before extraction.
UNSAFE_SRC="$TEST_ROOT/unsafe-src"
mkdir -p "$UNSAFE_SRC/go/bin"
cp "$FIXTURE/go/bin/go" "$UNSAFE_SRC/go/bin/go"
cp "$FIXTURE/go/bin/gofmt" "$UNSAFE_SRC/go/bin/gofmt"
ln -s /tmp "$UNSAFE_SRC/go/escape"
UNSAFE_ARCHIVE="$TEST_ROOT/unsafe.tar.gz"
tar -czf "$UNSAFE_ARCHIVE" -C "$UNSAFE_SRC" go
UNSAFE_SHA=$(sha256_file "$UNSAFE_ARCHIVE")
write_index "$UNSAFE_SHA"
CURRENT_ARCHIVE=$UNSAFE_ARCHIVE
if install_go_artifact linux amd64 >/dev/null 2>&1; then echo "Go symlink archive unexpectedly accepted" >&2; exit 1; fi
[ ! -e "$DEST" ]

# Wrong archive root is rejected.
WRONG_SRC="$TEST_ROOT/wrong-src"
mkdir -p "$WRONG_SRC/not-go/bin"
cp "$FIXTURE/go/bin/go" "$WRONG_SRC/not-go/bin/go"
cp "$FIXTURE/go/bin/gofmt" "$WRONG_SRC/not-go/bin/gofmt"
WRONG_ARCHIVE="$TEST_ROOT/wrong.tar.gz"
tar -czf "$WRONG_ARCHIVE" -C "$WRONG_SRC" not-go
WRONG_SHA=$(sha256_file "$WRONG_ARCHIVE")
write_index "$WRONG_SHA"
CURRENT_ARCHIVE=$WRONG_ARCHIVE
if install_go_artifact linux amd64 >/dev/null 2>&1; then echo "wrong-root Go archive unexpectedly accepted" >&2; exit 1; fi
[ ! -e "$DEST" ]

# State symlinks are fail-closed.
rm -f "$STATE_DIR/go-artifact.jsonl"
ln -s "$TEST_ROOT/elsewhere.jsonl" "$STATE_DIR/go-artifact.jsonl"
if go_artifact_state_ready; then echo "Go state symlink unexpectedly accepted" >&2; exit 1; fi
rm -f "$STATE_DIR/go-artifact.jsonl"
rmdir "$STATE_DIR"
mkdir "$TEST_ROOT/alternate-state"
ln -s "$TEST_ROOT/alternate-state" "$STATE_DIR"
if go_artifact_state_ready; then echo "Go state-directory symlink unexpectedly accepted" >&2; exit 1; fi

echo "verified Go artifact offline tests passed"

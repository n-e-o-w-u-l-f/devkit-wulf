#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-rustup-test.XXXXXX")
HOME="$TEST_ROOT/home with space"
STATE_DIR="$TEST_ROOT/state"
RUSTUP_ARTIFACT_MANIFEST="$ROOT/manifests/rustup-artifact.json"
ARGS_LOG="$TEST_ROOT/rustup-init-args.log"
DOWNLOAD_LOG="$TEST_ROOT/downloads.log"
export HOME STATE_DIR RUSTUP_ARTIFACT_MANIFEST ARGS_LOG
cleanup() { find "$TEST_ROOT" -type l -delete 2>/dev/null || true; find "$TEST_ROOT" -type f -delete 2>/dev/null || true; find "$TEST_ROOT" -depth -type d -exec rmdir {} \; 2>/dev/null || true; }
trap 'cleanup' EXIT HUP INT TERM

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }
mkdir -p "$HOME/.local/share" "$STATE_DIR"
CARGO_HOME="$HOME/.local/share/devkit-wulf/cargo"
RUSTUP_HOME="$HOME/.local/share/devkit-wulf/rustup"
PATH_DIR="$CARGO_HOME/bin"
PATH="$PATH_DIR:$PATH"
export PATH

FAKE_INIT="$TEST_ROOT/rustup-init"
cat > "$FAKE_INIT" <<'EOF'
#!/bin/sh
set -eu
: "${CARGO_HOME:?}"
: "${RUSTUP_HOME:?}"
: "${ARGS_LOG:?}"
printf '%s\n' "$@" > "$ARGS_LOG"
mkdir -p "$CARGO_HOME/bin" "$RUSTUP_HOME"
for name in rustup rustc cargo; do
  cat > "$CARGO_HOME/bin/$name" <<SCRIPT
#!/bin/sh
printf '%s fixture 1.0.0\\n' '$name'
SCRIPT
  chmod 0755 "$CARGO_HOME/bin/$name"
done
EOF
chmod 0755 "$FAKE_INIT"

have() { command -v "$1" >/dev/null 2>&1; }
die() { printf '%s\n' "$*" >&2; exit 1; }
sha256_file() {
  file=$1
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$file" | awk '{print $1}'
  else printf unavailable
  fi
}
INIT_SHA=$(sha256_file "$FAKE_INIT")
[ "$INIT_SHA" != unavailable ] || { echo "SHA-256 implementation required" >&2; exit 1; }
: > "$DOWNLOAD_LOG"
download_https() {
  url=$1 dest=$2
  printf '%s\n' "$url" >> "$DOWNLOAD_LOG"
  case "$url" in
    https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init) cp "$FAKE_INIT" "$dest" ;;
    https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init.sha256) printf '%s  rustup-init\n' "$INIT_SHA" > "$dest" ;;
    *) echo "unexpected fixture URL: $url" >&2; return 97 ;;
  esac
}

# shellcheck source=../lib/rustup-artifact.sh
. "$ROOT/lib/rustup-artifact.sh"
rustup_artifact_glibc_available() { return 0; }

[ "$(rustup_artifact_triple linux amd64)" = x86_64-unknown-linux-gnu ]
[ "$(rustup_artifact_triple linux arm64)" = aarch64-unknown-linux-gnu ]
[ "$(rustup_artifact_triple macos amd64)" = x86_64-apple-darwin ]
[ "$(rustup_artifact_triple macos arm64)" = aarch64-apple-darwin ]
[ "$(rustup_artifact_source_url linux amd64)" = 'https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init' ]
[ "$(rustup_artifact_checksum_url linux amd64)" = 'https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init.sha256' ]
if rustup_artifact_target_json linux riscv64 | grep -q .; then echo "unmapped rustup architecture unexpectedly resolved" >&2; exit 1; fi

# Helper calls must not overwrite common caller variable names when sourced.
platform=caller-platform
arch=caller-arch
source=caller-source
plan=$(plan_rustup_artifact linux amd64)
[ "$platform" = caller-platform ] && [ "$arch" = caller-arch ] && [ "$source" = caller-source ]
printf '%s\n' "$plan" | grep 'target_triple: x86_64-unknown-linux-gnu' >/dev/null
printf '%s\n' "$plan" | grep 'integrity: sha256' >/dev/null
printf '%s\n' "$plan" | grep 'remote_script_execution: false' >/dev/null
printf '%s\n' "$plan" | grep 'path_mutation: none' >/dev/null
printf '%s\n' "$plan" | grep 'privilege: none' >/dev/null
printf '%s\n' "$plan" | grep 'mutates_host: false' >/dev/null
printf '%s\n' "$plan" | grep "cargo_home: $CARGO_HOME" >/dev/null
[ ! -e "$CARGO_HOME" ] && [ ! -e "$RUSTUP_HOME" ]

install_rustup_artifact linux amd64
verify_rustup_artifact linux amd64
[ -f "$CARGO_HOME/.devkit-wulf-rustup.json" ]
[ -x "$CARGO_HOME/bin/rustup" ] && [ -x "$CARGO_HOME/bin/rustc" ] && [ -x "$CARGO_HOME/bin/cargo" ]
for arg in -y --profile minimal --default-toolchain stable --no-modify-path; do grep -Fx -- "$arg" "$ARGS_LOG" >/dev/null; done
[ "$(sed -n '1p' "$STATE_DIR/rustup-artifact.jsonl" | jq -r '.action')" = mutation-intent ]
[ "$(tail -n 1 "$STATE_DIR/rustup-artifact.jsonl" | jq -r '.action')" = installed-verified ]

# Exact managed second install is fully offline.
: > "$DOWNLOAD_LOG"
install_rustup_artifact linux amd64
[ ! -s "$DOWNLOAD_LOG" ]
[ "$(tail -n 1 "$STATE_DIR/rustup-artifact.jsonl" | jq -r '.action')" = observed-managed ]

# Marker-bound binary tampering fails verification.
printf '\n# tampered\n' >> "$CARGO_HOME/bin/cargo"
if verify_rustup_artifact linux amd64; then echo "tampered cargo unexpectedly verified" >&2; exit 1; fi
find "$CARGO_HOME" "$RUSTUP_HOME" -type f -delete 2>/dev/null || true
find "$CARGO_HOME" "$RUSTUP_HOME" -depth -type d -exec rmdir {} \; 2>/dev/null || true

# Foreign homes are rejected before network access.
mkdir -p "$CARGO_HOME"
: > "$DOWNLOAD_LOG"
if install_rustup_artifact linux amd64 >/dev/null 2>&1; then echo "foreign cargo home unexpectedly adopted" >&2; exit 1; fi
[ ! -s "$DOWNLOAD_LOG" ]
rmdir "$CARGO_HOME"

# Missing PATH declaration is rejected before network access.
OLD_PATH=$PATH
PATH=$(printf '%s' "$PATH" | awk -v RS=: -v ORS=: -v x="$PATH_DIR" '$0 != x {print}' | sed 's/:$//')
export PATH
: > "$DOWNLOAD_LOG"
if install_rustup_artifact linux amd64 >/dev/null 2>&1; then echo "missing rustup PATH declaration unexpectedly accepted" >&2; exit 1; fi
[ ! -s "$DOWNLOAD_LOG" ]
PATH=$OLD_PATH
export PATH

# Checksum mismatch fails before managed homes are created.
download_https() {
  url=$1 dest=$2
  printf '%s\n' "$url" >> "$DOWNLOAD_LOG"
  case "$url" in
    *.sha256) printf '%064d\n' 0 > "$dest" ;;
    */rustup-init) cp "$FAKE_INIT" "$dest" ;;
    *) return 97 ;;
  esac
}
: > "$DOWNLOAD_LOG"
if install_rustup_artifact linux amd64 >/dev/null 2>&1; then echo "rustup checksum mismatch unexpectedly accepted" >&2; exit 1; fi
[ ! -e "$CARGO_HOME" ] && [ ! -e "$RUSTUP_HOME" ]

# State symlinks are fail-closed.
rm -f "$STATE_DIR/rustup-artifact.jsonl"
ln -s "$TEST_ROOT/elsewhere.jsonl" "$STATE_DIR/rustup-artifact.jsonl"
if rustup_artifact_state_ready; then echo "rustup state symlink unexpectedly accepted" >&2; exit 1; fi
rm -f "$STATE_DIR/rustup-artifact.jsonl"
rmdir "$STATE_DIR"
mkdir "$TEST_ROOT/alternate-state"
ln -s "$TEST_ROOT/alternate-state" "$STATE_DIR"
if rustup_artifact_state_ready; then echo "rustup state-directory symlink unexpectedly accepted" >&2; exit 1; fi

# Linux artifact is explicitly glibc-only.
rustup_artifact_glibc_available() { return 1; }
if rustup_artifact_target_compatible linux amd64; then echo "non-glibc Linux unexpectedly accepted" >&2; exit 1; fi

echo "verified rustup-init offline artifact tests passed"

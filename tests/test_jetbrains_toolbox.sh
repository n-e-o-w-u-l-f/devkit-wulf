#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-jetbrains-test.XXXXXX")
STATE_DIR="$TEST_ROOT/state"
JETBRAINS_TOOLBOX_MANIFEST="$TEST_ROOT/jetbrains-toolbox.json"
cleanup_test_root() {
  find "$TEST_ROOT" -type l -delete 2>/dev/null || true
  find "$TEST_ROOT" -type f -delete 2>/dev/null || true
  find "$TEST_ROOT" -depth -type d -exec rmdir {} \; 2>/dev/null || true
}
trap 'cleanup_test_root' EXIT HUP INT TERM

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar required" >&2; exit 1; }

HOME="$TEST_ROOT/home"
mkdir -p "$HOME/.local/bin" "$STATE_DIR" "$TEST_ROOT/archive-src/jetbrains-toolbox-3.1.2.12345"
export HOME STATE_DIR JETBRAINS_TOOLBOX_MANIFEST
PATH="$HOME/.local/bin:$PATH"
export PATH

printf '#!/bin/sh\nprintf "JetBrains Toolbox 3.1.2.12345\\n"\n' > "$TEST_ROOT/archive-src/jetbrains-toolbox-3.1.2.12345/jetbrains-toolbox"
chmod 0755 "$TEST_ROOT/archive-src/jetbrains-toolbox-3.1.2.12345/jetbrains-toolbox"
ARCHIVE="$TEST_ROOT/jetbrains-toolbox-3.1.2.12345.tar.gz"
tar -czf "$ARCHIVE" -C "$TEST_ROOT/archive-src" jetbrains-toolbox-3.1.2.12345

have() { command -v "$1" >/dev/null 2>&1; }
log() { :; }
warn() { :; }
die() { printf '%s\n' "$*" >&2; exit 1; }
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
ARCHIVE_SHA=$(sha256_file "$ARCHIVE")
[ "$ARCHIVE_SHA" != unavailable ] || { echo "SHA-256 implementation required" >&2; exit 1; }

cat > "$JETBRAINS_TOOLBOX_MANIFEST" <<'EOF'
{
  "schema_version": 1,
  "research_date": "2026-08-11",
  "publisher": "JetBrains s.r.o.",
  "product_code": "TBA",
  "release_type": "release",
  "api_url": "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release",
  "version_pattern": "^[0-9]+(\\.[0-9]+){2,3}$",
  "allowed_download_hosts": ["download.jetbrains.com", "download-cdn.jetbrains.com"],
  "targets": {
    "linux": {
      "archive_format": "tar.gz",
      "destination_template": "{home}/.local/bin/jetbrains-toolbox",
      "path_directory_template": "{home}/.local/bin",
      "marker_template": "{home}/.local/bin/.jetbrains-toolbox.devkit-wulf.json",
      "root_directory_template": "jetbrains-toolbox-{version}",
      "executable_relative_path": "jetbrains-toolbox",
      "architectures": {
        "amd64": {"download_key": "linux"},
        "arm64": {"download_key": "linuxARM64"}
      }
    }
  }
}
EOF

cat > "$TEST_ROOT/releases.json" <<EOF
{
  "TBA": [
    {
      "date": "2026-08-11",
      "type": "release",
      "version": "3.1.2.12345",
      "downloads": {
        "linux": {
          "link": "https://download.jetbrains.com/toolbox/jetbrains-toolbox-3.1.2.12345.tar.gz",
          "checksumLink": "https://download.jetbrains.com/toolbox/jetbrains-toolbox-3.1.2.12345.tar.gz.sha256"
        },
        "linuxARM64": {
          "link": "https://download-cdn.jetbrains.com/toolbox/jetbrains-toolbox-3.1.2.12345-arm64.tar.gz",
          "checksumLink": "https://download-cdn.jetbrains.com/toolbox/jetbrains-toolbox-3.1.2.12345-arm64.tar.gz.sha256"
        }
      }
    }
  ]
}
EOF

DOWNLOAD_LOG="$TEST_ROOT/downloads.log"
: > "$DOWNLOAD_LOG"
download_https() {
  url=$1
  dest=$2
  printf '%s\n' "$url" >> "$DOWNLOAD_LOG"
  case "$url" in
    'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release') cp "$TEST_ROOT/releases.json" "$dest" ;;
    https://download.jetbrains.com/toolbox/jetbrains-toolbox-3.1.2.12345.tar.gz) cp "$ARCHIVE" "$dest" ;;
    https://download.jetbrains.com/toolbox/jetbrains-toolbox-3.1.2.12345.tar.gz.sha256) printf '%s  jetbrains-toolbox-3.1.2.12345.tar.gz\n' "$ARCHIVE_SHA" > "$dest" ;;
    https://download-cdn.jetbrains.com/toolbox/jetbrains-toolbox-3.1.2.12345-arm64.tar.gz) cp "$ARCHIVE" "$dest" ;;
    https://download-cdn.jetbrains.com/toolbox/jetbrains-toolbox-3.1.2.12345-arm64.tar.gz.sha256) printf '%s\n' "$ARCHIVE_SHA" > "$dest" ;;
    *) echo "unexpected fixture URL: $url" >&2; return 97 ;;
  esac
}

# shellcheck source=../lib/jetbrains-toolbox.sh
. "$ROOT/lib/jetbrains-toolbox.sh"

amd64_target=$(jetbrains_toolbox_target_json amd64)
[ "$(printf '%s' "$amd64_target" | jq -r '.download_key')" = linux ]
arm64_target=$(jetbrains_toolbox_target_json arm64)
[ "$(printf '%s' "$arm64_target" | jq -r '.download_key')" = linuxARM64 ]
if jetbrains_toolbox_target_json riscv64 | grep -q .; then echo "unmapped architecture unexpectedly resolved" >&2; exit 1; fi

release=$(jetbrains_toolbox_resolve_release amd64)
[ "$(printf '%s' "$release" | jq -r '.version')" = 3.1.2.12345 ]
[ "$(printf '%s' "$release" | jq -r '.root_directory')" = jetbrains-toolbox-3.1.2.12345 ]
[ "$(printf '%s' "$release" | jq -r '.download_key')" = linux ]

plan=$(plan_jetbrains_toolbox amd64)
printf '%s\n' "$plan" | grep 'publisher: JetBrains s.r.o.' >/dev/null
printf '%s\n' "$plan" | grep 'resolved_version: 3.1.2.12345' >/dev/null
printf '%s\n' "$plan" | grep 'integrity: sha256-link' >/dev/null
printf '%s\n' "$plan" | grep "destination: $HOME/.local/bin/jetbrains-toolbox" >/dev/null
printf '%s\n' "$plan" | grep 'path_mutation: none' >/dev/null

install_jetbrains_toolbox amd64
DEST="$HOME/.local/bin/jetbrains-toolbox"
MARKER="$HOME/.local/bin/.jetbrains-toolbox.devkit-wulf.json"
[ -x "$DEST" ]
[ -f "$MARKER" ]
verify_jetbrains_toolbox amd64
"$DEST" --version | grep '3.1.2.12345' >/dev/null
EXEC_SHA=$(sha256_file "$DEST")
jq -e --arg a "$ARCHIVE_SHA" --arg e "$EXEC_SHA" '.environment == "jetbrains" and .version == "3.1.2.12345" and .archive_sha256 == $a and .executable_sha256 == $e' "$MARKER" >/dev/null
grep '"action":"installed-verified-artifact"' "$STATE_DIR/jetbrains-toolbox.jsonl" >/dev/null

# Exact second install must be idempotent.
install_jetbrains_toolbox amd64
verify_jetbrains_toolbox amd64
grep '"action":"observed-exact-artifact"' "$STATE_DIR/jetbrains-toolbox.jsonl" >/dev/null

# A modified managed binary invalidates offline managed verification.
printf '\n# tampered\n' >> "$DEST"
if verify_jetbrains_toolbox amd64; then echo "tampered managed binary unexpectedly verified" >&2; exit 1; fi
# Restore from archive fixture without changing marker semantics.
tar -xOf "$ARCHIVE" jetbrains-toolbox-3.1.2.12345/jetbrains-toolbox > "$DEST"
chmod 0755 "$DEST"
verify_jetbrains_toolbox amd64

# Marker loss means ownership can no longer be proven; do not adopt the binary.
rm -f "$MARKER"
if verify_jetbrains_toolbox amd64; then echo "markerless binary unexpectedly verified" >&2; exit 1; fi
if install_jetbrains_toolbox amd64 >/dev/null 2>&1; then echo "unowned existing JetBrains Toolbox binary unexpectedly accepted" >&2; exit 1; fi

rm -f "$DEST"
: > "$DOWNLOAD_LOG"

# A checksum mismatch must hard-fail before destination mutation.
BAD_SHA=$(printf '0%.0s' $(seq 1 64))
download_https() {
  url=$1
  dest=$2
  printf '%s\n' "$url" >> "$DOWNLOAD_LOG"
  case "$url" in
    'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release') cp "$TEST_ROOT/releases.json" "$dest" ;;
    https://download.jetbrains.com/toolbox/jetbrains-toolbox-3.1.2.12345.tar.gz) cp "$ARCHIVE" "$dest" ;;
    https://download.jetbrains.com/toolbox/jetbrains-toolbox-3.1.2.12345.tar.gz.sha256) printf '%s\n' "$BAD_SHA" > "$dest" ;;
    *) return 97 ;;
  esac
}
if install_jetbrains_toolbox amd64 >/dev/null 2>&1; then echo "checksum mismatch unexpectedly accepted" >&2; exit 1; fi
[ ! -e "$DEST" ]

# An unapproved download host in official-looking JSON must fail at GATE-04.
jq '.TBA[0].downloads.linux.link = "https://evil.example/jetbrains-toolbox.tar.gz"' "$TEST_ROOT/releases.json" > "$TEST_ROOT/releases-bad-host.json"
download_https() {
  url=$1
  dest=$2
  case "$url" in
    'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release') cp "$TEST_ROOT/releases-bad-host.json" "$dest" ;;
    *) echo "unexpected network access after bad host metadata: $url" >&2; return 96 ;;
  esac
}
if jetbrains_toolbox_resolve_release amd64 >/dev/null 2>&1; then echo "unapproved JetBrains download host unexpectedly accepted" >&2; exit 1; fi

# Archive content must remain under the exact versioned root.
mkdir -p "$TEST_ROOT/wrong-root/not-toolbox"
printf '#!/bin/sh\n' > "$TEST_ROOT/wrong-root/not-toolbox/jetbrains-toolbox"
chmod 0755 "$TEST_ROOT/wrong-root/not-toolbox/jetbrains-toolbox"
tar -czf "$TEST_ROOT/wrong-root.tar.gz" -C "$TEST_ROOT/wrong-root" not-toolbox
if jetbrains_toolbox_archive_safe "$TEST_ROOT/wrong-root.tar.gz" jetbrains-toolbox-3.1.2.12345 jetbrains-toolbox "$TEST_ROOT/wrong.list"; then
  echo "wrong archive root unexpectedly accepted" >&2
  exit 1
fi

# State symlinks remain fail-closed.
rm -f "$STATE_DIR/jetbrains-toolbox.jsonl"
ln -s "$TEST_ROOT/elsewhere.jsonl" "$STATE_DIR/jetbrains-toolbox.jsonl"
if jetbrains_toolbox_state_ready; then echo "JetBrains state symlink unexpectedly accepted" >&2; exit 1; fi
rm -f "$STATE_DIR/jetbrains-toolbox.jsonl"
rmdir "$STATE_DIR"
mkdir "$TEST_ROOT/alternate-state"
ln -s "$TEST_ROOT/alternate-state" "$STATE_DIR"
if jetbrains_toolbox_state_ready; then echo "JetBrains state-directory symlink unexpectedly accepted" >&2; exit 1; fi

echo "JetBrains Toolbox offline artifact tests passed"

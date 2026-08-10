#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REAL_ARTIFACT_MANIFEST="$ROOT/manifests/artifacts.json"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-artifact-test.XXXXXX")
STATE_DIR="$TEST_ROOT/state"
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }
log() { :; }
warn() { :; }
die() { echo "$*" >&2; exit 1; }

sha256_file() {
  file=$1
  if have sha256sum; then sha256sum "$file" | awk '{print $1}'
  elif have shasum; then shasum -a 256 "$file" | awk '{print $1}'
  else printf unavailable
  fi
}

privileged() {
  echo "unexpected privileged execution in isolated artifact test" >&2
  return 98
}

# Defined before sourcing; integration tests replace its behavior with local fixtures.
download_https() { return 99; }

ARTIFACT_MANIFEST="$REAL_ARTIFACT_MANIFEST"
# shellcheck source=../lib/artifacts.sh
. "$ROOT/lib/artifacts.sh"

artifact_definition_exists kubectl

target=$(artifact_target_json kubectl debian debian amd64)
[ "$(printf '%s' "$target" | jq -r '.destination')" = /usr/local/bin/kubectl ]
[ "$(printf '%s' "$target" | jq -r '.integrity')" = sha256 ]
[ "$(printf '%s' "$target" | jq -r '.privileged')" = true ]
[ "$(printf '%s' "$target" | jq -r '.filename')" = kubectl ]

artifact_validate_version v1.36.3 '^v[0-9]+\.[0-9]+\.[0-9]+$'
if artifact_validate_version '../bad' '^.*$'; then
  echo "unsafe version token unexpectedly accepted" >&2
  exit 1
fi

url=$(artifact_render_template 'https://dl.k8s.io/release/{version}/bin/linux/amd64/kubectl' v1.36.3)
[ "$url" = 'https://dl.k8s.io/release/v1.36.3/bin/linux/amd64/kubectl' ]

if artifact_target_json kubectl debian debian riscv64 | grep -q .; then
  echo "unmapped kubectl architecture unexpectedly resolved" >&2
  exit 1
fi

# Isolated end-to-end fixture: no network, no privilege, no host mutation.
mkdir -p "$TEST_ROOT/bin" "$STATE_DIR"
PAYLOAD="$TEST_ROOT/source-tool"
printf '#!/bin/sh\nprintf "fixture-tool 1.2.3\\n"\n' > "$PAYLOAD"
chmod 0755 "$PAYLOAD"
EXPECTED=$(sha256_file "$PAYLOAD")
[ "$EXPECTED" != unavailable ] || { echo "SHA-256 implementation required" >&2; exit 1; }

ARTIFACT_MANIFEST="$TEST_ROOT/artifacts.json"
cat > "$ARTIFACT_MANIFEST" <<EOF
{
  "schema_version": 1,
  "research_date": "2026-08-11",
  "artifacts": {
    "fixture": {
      "publisher": "Fixture Publisher",
      "source": "https://example.invalid/docs",
      "version": {
        "resolver": "text-url",
        "url": "https://example.invalid/stable.txt",
        "pattern": "^v[0-9]+[.][0-9]+[.][0-9]+$"
      },
      "targets": {
        "linux": {
          "destination": "$TEST_ROOT/bin/fixture-tool",
          "path_directory": "$TEST_ROOT/bin",
          "mode": "0755",
          "integrity": "sha256",
          "privileged": false,
          "architectures": {
            "amd64": {
              "filename": "fixture-tool",
              "url_template": "https://example.invalid/{version}/linux/amd64/fixture-tool",
              "checksum_url_template": "https://example.invalid/{version}/linux/amd64/fixture-tool.sha256"
            }
          }
        }
      }
    }
  }
}
EOF

PATH="$TEST_ROOT/bin:$PATH"
export PATH

download_https() {
  url=$1
  dest=$2
  case "$url" in
    https://example.invalid/stable.txt)
      printf 'v1.2.3\n' > "$dest"
      ;;
    https://example.invalid/v1.2.3/linux/amd64/fixture-tool)
      cp "$PAYLOAD" "$dest"
      ;;
    https://example.invalid/v1.2.3/linux/amd64/fixture-tool.sha256)
      printf '%s\n' "$EXPECTED" > "$dest"
      ;;
    *)
      echo "unexpected fixture URL: $url" >&2
      return 97
      ;;
  esac
}

plan=$(plan_verified_artifact fixture linux linux amd64)
printf '%s\n' "$plan" | grep 'resolved_version: v1.2.3' >/dev/null
printf '%s\n' "$plan" | grep 'integrity: sha256' >/dev/null
printf '%s\n' "$plan" | grep 'privilege: none' >/dev/null
printf '%s\n' "$plan" | grep 'path_mutation: none' >/dev/null

install_verified_artifact fixture linux linux amd64
[ -x "$TEST_ROOT/bin/fixture-tool" ]
[ "$(sha256_file "$TEST_ROOT/bin/fixture-tool")" = "$EXPECTED" ]
jq -e 'select(.environment == "fixture" and .publisher == "Fixture Publisher" and .action == "installed-verified-artifact" and .created == true and .path_mutation == false)' "$STATE_DIR/artifacts.jsonl" >/dev/null

# Exact second installation is idempotent and records observation rather than mutation.
install_verified_artifact fixture linux linux amd64
tail -n 1 "$STATE_DIR/artifacts.jsonl" | jq -e 'select(.action == "observed-exact-artifact" and .created == false)' >/dev/null

# Symlink destinations are an explicit conflict even when they resolve to the same payload.
rm -f "$TEST_ROOT/bin/fixture-tool"
ln -s "$PAYLOAD" "$TEST_ROOT/bin/fixture-tool"
if install_verified_artifact fixture linux linux amd64 >/dev/null 2>&1; then
  echo "symlink destination unexpectedly accepted" >&2
  exit 1
fi

# A different regular file is never overwritten implicitly.
rm -f "$TEST_ROOT/bin/fixture-tool"
printf 'different\n' > "$TEST_ROOT/bin/fixture-tool"
if install_verified_artifact fixture linux linux amd64 >/dev/null 2>&1; then
  echo "different existing artifact unexpectedly overwritten" >&2
  exit 1
fi
[ "$(cat "$TEST_ROOT/bin/fixture-tool")" = different ]

echo "artifact helper and isolated install tests passed"

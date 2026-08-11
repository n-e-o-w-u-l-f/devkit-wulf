#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-repository-test.XXXXXX")
STATE_DIR="$TEST_ROOT/state"
REPOSITORY_MANIFEST="$TEST_ROOT/repositories.json"
LOG_FILE="$TEST_ROOT/commands.log"
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/etc/apt/keyrings" "$TEST_ROOT/etc/apt/sources.list.d" "$STATE_DIR"

cat > "$TEST_ROOT/bin/apt-get" <<'EOF'
#!/bin/sh
printf 'apt-get %s\n' "$*" >> "$DEVKIT_WULF_TEST_LOG"
EOF
chmod 0755 "$TEST_ROOT/bin/apt-get"

# The fixture uses non-secret dummy bytes as key material. A fake GPG parser keeps
# this integration test offline while production code still requires a real gpg/gpg2.
cat > "$TEST_ROOT/bin/gpg" <<'EOF'
#!/bin/sh
case " $* " in
  *" --show-keys "*) exit 0 ;;
  *) echo "unexpected fixture gpg invocation: $*" >&2; exit 92 ;;
esac
EOF
chmod 0755 "$TEST_ROOT/bin/gpg"

PATH="$TEST_ROOT/bin:$PATH"
export PATH DEVKIT_WULF_TEST_LOG="$LOG_FILE"

KEY_SOURCE="$TEST_ROOT/source-key.gpg"
printf 'fixture repository key\n' > "$KEY_SOURCE"

cat > "$REPOSITORY_MANIFEST" <<EOF
{
  "schema_version": 1,
  "research_date": "2026-08-11",
  "repositories": {
    "fixture": {
      "publisher": "Fixture Publisher",
      "targets": {
        "debian": {
          "documentation": "https://example.invalid/docs",
          "package_manager": "apt",
          "package": "fixture-package",
          "prerequisites": ["fixture-prerequisite"],
          "key_directory": "$TEST_ROOT/etc/apt/keyrings",
          "keys": [
            {
              "url": "https://example.invalid/key.gpg",
              "destination": "$TEST_ROOT/etc/apt/keyrings/fixture.gpg",
              "transform": "copy"
            }
          ],
          "repository_file": "$TEST_ROOT/etc/apt/sources.list.d/fixture.list",
          "repository_content": "deb [signed-by=$TEST_ROOT/etc/apt/keyrings/fixture.gpg] https://example.invalid/packages stable main\\n",
          "package_signature_required": true,
          "repository_signature_required": true,
          "tls_verification_required": true
        }
      }
    }
  },
  "native_packages": {}
}
EOF

have() { command -v "$1" >/dev/null 2>&1; }
log() { :; }
warn() { :; }
die() { printf '%s\n' "$*" >&2; exit 1; }
privileged() { "$@"; }
install_packages() {
  printf 'install_packages %s\n' "$*" >> "$LOG_FILE"
}
download_https() {
  url=$1
  dest=$2
  [ "$url" = "https://example.invalid/key.gpg" ] || { echo "unexpected URL: $url" >&2; return 91; }
  cp "$KEY_SOURCE" "$dest"
}
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

# shellcheck source=../lib/repositories.sh
. "$ROOT/lib/repositories.sh"

repository_definition_exists fixture
[ -n "$(repository_target_json fixture debian)" ]

plan=$(plan_vendor_repository fixture debian apt)
printf '%s\n' "$plan" | grep 'publisher: Fixture Publisher' >/dev/null
printf '%s\n' "$plan" | grep 'package_manager: apt' >/dev/null
printf '%s\n' "$plan" | grep 'package_signature_required: true' >/dev/null
printf '%s\n' "$plan" | grep 'privilege: required-for-package-and-repository-mutation' >/dev/null
printf '%s\n' "$plan" | grep 'conflict_policy: preflight-refuse-existing-different-content' >/dev/null

install_vendor_repository fixture debian apt
[ -f "$TEST_ROOT/etc/apt/keyrings/fixture.gpg" ]
[ -f "$TEST_ROOT/etc/apt/sources.list.d/fixture.list" ]
grep 'install_packages apt fixture-prerequisite' "$LOG_FILE" >/dev/null
grep 'install_packages apt fixture-package' "$LOG_FILE" >/dev/null
grep 'apt-get update' "$LOG_FILE" >/dev/null
grep '"action":"mutation-intent"' "$STATE_DIR/repositories.jsonl" >/dev/null
grep '"action":"installed-resource"' "$STATE_DIR/repositories.jsonl" >/dev/null

# A second installation must accept byte-identical managed resources.
install_vendor_repository fixture debian apt
grep '"action":"observed-exact-resource"' "$STATE_DIR/repositories.jsonl" >/dev/null

# A different existing repository file must fail before package/repository mutation.
printf 'foreign repository content\n' > "$TEST_ROOT/etc/apt/sources.list.d/fixture.list"
: > "$LOG_FILE"
state_lines_before=$(wc -l < "$STATE_DIR/repositories.jsonl" | tr -d ' ')
if install_vendor_repository fixture debian apt >/dev/null 2>&1; then
  echo "different repository file unexpectedly overwritten" >&2
  exit 1
fi
grep 'foreign repository content' "$TEST_ROOT/etc/apt/sources.list.d/fixture.list" >/dev/null
[ ! -s "$LOG_FILE" ] || { echo "package mutation occurred before conflict gate" >&2; cat "$LOG_FILE" >&2; exit 1; }
state_lines_after=$(wc -l < "$STATE_DIR/repositories.jsonl" | tr -d ' ')
[ "$state_lines_before" = "$state_lines_after" ] || { echo "state mutation occurred before conflict gate" >&2; exit 1; }

# Repository state must never follow a file symlink.
rm -f "$STATE_DIR/repositories.jsonl"
ln -s "$TEST_ROOT/elsewhere.jsonl" "$STATE_DIR/repositories.jsonl"
if repository_state_ready >/dev/null 2>&1; then
  echo "repository state symlink unexpectedly accepted" >&2
  exit 1
fi

# Repository state must also refuse a symlinked state directory.
rm -f "$STATE_DIR/repositories.jsonl"
rmdir "$STATE_DIR"
mkdir "$TEST_ROOT/alternate-state"
ln -s "$TEST_ROOT/alternate-state" "$STATE_DIR"
if repository_state_ready >/dev/null 2>&1; then
  echo "repository state-directory symlink unexpectedly accepted" >&2
  exit 1
fi

printf 'vendor repository helper tests passed\n'

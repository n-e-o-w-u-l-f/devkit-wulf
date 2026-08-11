#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-repository-test.XXXXXX")
STATE_DIR="$TEST_ROOT/state"
REPOSITORY_MANIFEST="$TEST_ROOT/repositories.json"
LOG_FILE="$TEST_ROOT/commands.log"
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

mkdir -p \
  "$TEST_ROOT/bin" \
  "$TEST_ROOT/etc/apt/keyrings" \
  "$TEST_ROOT/etc/apt/sources.list.d" \
  "$TEST_ROOT/etc/yum.repos.d" \
  "$TEST_ROOT/etc/pki/rpm-gpg" \
  "$STATE_DIR"

cat > "$TEST_ROOT/bin/apt-get" <<'EOF'
#!/bin/sh
printf 'apt-get %s\n' "$*" >> "$DEVKIT_WULF_TEST_LOG"
EOF

cat > "$TEST_ROOT/bin/dpkg" <<'EOF'
#!/bin/sh
[ "${1:-}" = --print-architecture ] || exit 90
printf 'amd64\n'
EOF

cat > "$TEST_ROOT/bin/dpkg-query" <<'EOF'
#!/bin/sh
package=
for arg in "$@"; do package=$arg; done
if [ "${DEVKIT_WULF_TEST_CONFLICT:-0}" = 1 ] && [ "$package" = foreign-package ]; then
  printf 'install ok installed'
  exit 0
fi
exit 1
EOF

cat > "$TEST_ROOT/bin/rpm" <<'EOF'
#!/bin/sh
exit 1
EOF

cat > "$TEST_ROOT/bin/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl %s\n' "$*" >> "$DEVKIT_WULF_TEST_LOG"
EOF

# Offline OpenPGP fixture parser. Production still requires real gpg/gpg2.
cat > "$TEST_ROOT/bin/gpg" <<'EOF'
#!/bin/sh
show_keys=false
dearmor=false
output=
input=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --show-keys) show_keys=true ;;
    --dearmor) dearmor=true ;;
    --output)
      shift
      [ "$#" -gt 0 ] || exit 93
      output=$1
      ;;
    --no-tty|--batch|--with-colons) ;;
    *) input=$1 ;;
  esac
  shift
done
if [ "$show_keys" = true ]; then
  [ -n "$input" ] || exit 94
  printf 'fpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:\n'
  exit 0
fi
if [ "$dearmor" = true ]; then
  [ -n "$input" ] && [ -n "$output" ] || exit 95
  cp "$input" "$output"
  exit 0
fi
echo "unexpected fixture gpg invocation" >&2
exit 92
EOF

chmod 0755 "$TEST_ROOT/bin/"*
PATH="$TEST_ROOT/bin:$PATH"
export PATH DEVKIT_WULF_TEST_LOG="$LOG_FILE"

KEY_SOURCE="$TEST_ROOT/source-key.gpg"
printf 'fixture repository key\n' > "$KEY_SOURCE"

cat > "$REPOSITORY_MANIFEST" <<EOF
{
  "schema_version": 2,
  "research_date": "2026-08-11",
  "repositories": {
    "fixture": {
      "publisher": "Fixture Publisher",
      "targets": {
        "platform:debian": {
          "documentation": "https://example.invalid/debian-docs",
          "package_manager": "apt",
          "packages": ["fixture-package", "fixture-plugin"],
          "prerequisites": ["fixture-prerequisite"],
          "conflicting_packages": ["foreign-package"],
          "architectures": ["amd64"],
          "supported_versions": ["12"],
          "key_directory": "$TEST_ROOT/etc/apt/keyrings",
          "keys": [
            {
              "url": "https://example.invalid/key.gpg",
              "destination": "$TEST_ROOT/etc/apt/keyrings/fixture.gpg",
              "transform": "copy",
              "fingerprint": "AAAA AAAA AAAA AAAA AAAA AAAA AAAA AAAA AAAA AAAA"
            }
          ],
          "repository_file": "$TEST_ROOT/etc/apt/sources.list.d/fixture.sources",
          "repository_content_template": "Types: deb\\nURIs: https://example.invalid/packages\\nSuites: {suite}\\nArchitectures: {architecture}\\nSigned-By: $TEST_ROOT/etc/apt/keyrings/fixture.gpg\\n",
          "suite_resolver": "debian-codename",
          "architecture_resolver": "dpkg",
          "package_signature_required": true,
          "repository_signature_required": true,
          "tls_verification_required": true
        },
        "family:debian": {
          "documentation": "https://example.invalid/family-docs",
          "package_manager": "apt",
          "package": "family-package",
          "prerequisites": [],
          "keys": [{"url": "https://example.invalid/key.gpg", "transform": "repository-key"}],
          "repository_file": "$TEST_ROOT/etc/apt/sources.list.d/family.list",
          "repository_content": "deb https://example.invalid/family stable main\\n",
          "package_signature_required": true,
          "repository_signature_required": true,
          "tls_verification_required": true
        }
      }
    },
    "remote": {
      "publisher": "Remote Fixture Publisher",
      "targets": {
        "platform:fedora": {
          "documentation": "https://example.invalid/fedora-docs",
          "package_manager": "dnf",
          "package": "remote-package",
          "prerequisites": [],
          "architectures": ["amd64"],
          "supported_versions": ["44"],
          "key_directory": "$TEST_ROOT/etc/pki/rpm-gpg",
          "keys": [
            {
              "url": "https://example.invalid/key.gpg",
              "destination": "$TEST_ROOT/etc/pki/rpm-gpg/remote.gpg",
              "transform": "copy",
              "fingerprint": "AAAA AAAA AAAA AAAA AAAA AAAA AAAA AAAA AAAA AAAA"
            }
          ],
          "repository_file": "$TEST_ROOT/etc/yum.repos.d/remote.repo",
          "repository_url": "https://example.invalid/remote.repo",
          "repository_required_substrings": ["gpgcheck=1", "https://example.invalid/key.gpg"],
          "localize_key_urls": true,
          "services": [{"name": "remote-service", "action": "enable-now"}],
          "package_signature_required": true,
          "repository_signature_required": false,
          "tls_verification_required": true
        }
      }
    }
  },
  "native_packages": {
    "native-fixture": {
      "opensuse-leap": {
        "documentation": "https://example.invalid/native-docs",
        "package_manager": "zypper",
        "package": "native-package",
        "services": [{"name": "native-service", "action": "enable-now"}]
      }
    }
  }
}
EOF

have() { command -v "$1" >/dev/null 2>&1; }
log() { :; }
warn() { :; }
die() { printf '%s\n' "$*" >&2; exit 1; }
privileged() { "$@"; }
install_packages() { printf 'install_packages %s\n' "$*" >> "$LOG_FILE"; }
read_os_release_value() {
  case "$1" in
    VERSION_CODENAME) printf bookworm ;;
    UBUNTU_CODENAME) printf noble ;;
    VERSION_ID) printf 12 ;;
    *) return 1 ;;
  esac
}
download_https() {
  url=$1
  dest=$2
  case "$url" in
    https://example.invalid/key.gpg) cp "$KEY_SOURCE" "$dest" ;;
    https://example.invalid/remote.repo)
      cat > "$dest" <<'EOF'
[remote]
name=remote
gpgcheck=1
gpgkey=https://example.invalid/key.gpg
sslverify=1
EOF
      ;;
    *) echo "unexpected URL: $url" >&2; return 91 ;;
  esac
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
[ "$(repository_target_key fixture debian debian)" = "platform:debian" ]
[ "$(repository_target_key fixture linuxmint debian)" = "family:debian" ]

exact_target=$(repository_target_json fixture debian debian)
[ "$(printf '%s' "$exact_target" | jq -r '.packages[0]')" = fixture-package ]
family_target=$(repository_target_json fixture linuxmint debian)
[ "$(printf '%s' "$family_target" | jq -r '.package')" = family-package ]

repository_target_compatible "$exact_target" amd64 12
repository_target_compatible "$exact_target" amd64 12.9
if repository_target_compatible "$exact_target" arm64 12; then
  echo "unsupported architecture unexpectedly accepted" >&2
  exit 1
fi
if repository_target_compatible "$exact_target" amd64 13; then
  echo "unsupported version unexpectedly accepted" >&2
  exit 1
fi

plan=$(plan_vendor_repository fixture debian debian apt amd64 12)
printf '%s\n' "$plan" | grep 'target: platform:debian' >/dev/null
printf '%s\n' "$plan" | grep 'publisher: Fixture Publisher' >/dev/null
printf '%s\n' "$plan" | grep 'fixture-plugin' >/dev/null
printf '%s\n' "$plan" | grep 'foreign-package' >/dev/null
printf '%s\n' "$plan" | grep 'fingerprint=AAAA AAAA' >/dev/null

install_vendor_repository fixture debian debian apt amd64 12
[ -f "$TEST_ROOT/etc/apt/keyrings/fixture.gpg" ]
[ -f "$TEST_ROOT/etc/apt/sources.list.d/fixture.sources" ]
grep '^Suites: bookworm$' "$TEST_ROOT/etc/apt/sources.list.d/fixture.sources" >/dev/null
grep '^Architectures: amd64$' "$TEST_ROOT/etc/apt/sources.list.d/fixture.sources" >/dev/null
grep 'install_packages apt fixture-prerequisite' "$LOG_FILE" >/dev/null
grep 'install_packages apt fixture-package fixture-plugin' "$LOG_FILE" >/dev/null
grep 'apt-get update' "$LOG_FILE" >/dev/null
grep '"action":"mutation-intent"' "$STATE_DIR/repositories.jsonl" >/dev/null
grep '"action":"installed-resource"' "$STATE_DIR/repositories.jsonl" >/dev/null

# A second install accepts exact managed resources.
install_vendor_repository fixture debian debian apt amd64 12
grep '"action":"observed-exact-resource"' "$STATE_DIR/repositories.jsonl" >/dev/null

# Package conflicts must block before any mutation or state change.
: > "$LOG_FILE"
state_lines_before=$(wc -l < "$STATE_DIR/repositories.jsonl" | tr -d ' ')
DEVKIT_WULF_TEST_CONFLICT=1
export DEVKIT_WULF_TEST_CONFLICT
if install_vendor_repository fixture debian debian apt amd64 12 >/dev/null 2>&1; then
  echo "installed conflicting package unexpectedly accepted" >&2
  exit 1
fi
unset DEVKIT_WULF_TEST_CONFLICT
[ ! -s "$LOG_FILE" ] || { echo "mutation occurred before package conflict gate" >&2; cat "$LOG_FILE" >&2; exit 1; }
state_lines_after=$(wc -l < "$STATE_DIR/repositories.jsonl" | tr -d ' ')
[ "$state_lines_before" = "$state_lines_after" ] || { echo "state changed before package conflict gate" >&2; exit 1; }

# A different repository file must also fail before package/repository mutation.
printf 'foreign repository content\n' > "$TEST_ROOT/etc/apt/sources.list.d/fixture.sources"
: > "$LOG_FILE"
state_lines_before=$(wc -l < "$STATE_DIR/repositories.jsonl" | tr -d ' ')
if install_vendor_repository fixture debian debian apt amd64 12 >/dev/null 2>&1; then
  echo "different repository file unexpectedly overwritten" >&2
  exit 1
fi
grep 'foreign repository content' "$TEST_ROOT/etc/apt/sources.list.d/fixture.sources" >/dev/null
[ ! -s "$LOG_FILE" ] || { echo "mutation occurred before repository conflict gate" >&2; exit 1; }
state_lines_after=$(wc -l < "$STATE_DIR/repositories.jsonl" | tr -d ' ')
[ "$state_lines_before" = "$state_lines_after" ] || { echo "state changed before repository conflict gate" >&2; exit 1; }

# Remote .repo staging verifies the key fingerprint, pins the verified key locally,
# rewrites gpgkey= to file://, and applies the declared service action.
: > "$LOG_FILE"
install_vendor_repository remote fedora fedora dnf amd64 44
[ -f "$TEST_ROOT/etc/pki/rpm-gpg/remote.gpg" ]
[ -f "$TEST_ROOT/etc/yum.repos.d/remote.repo" ]
grep 'gpgcheck=1' "$TEST_ROOT/etc/yum.repos.d/remote.repo" >/dev/null
grep "gpgkey=file://$TEST_ROOT/etc/pki/rpm-gpg/remote.gpg" "$TEST_ROOT/etc/yum.repos.d/remote.repo" >/dev/null
if grep -Fq 'gpgkey=https://example.invalid/key.gpg' "$TEST_ROOT/etc/yum.repos.d/remote.repo"; then
  echo "remote key URL remained after local pinning" >&2
  exit 1
fi
grep 'install_packages dnf remote-package' "$LOG_FILE" >/dev/null
grep 'systemctl enable --now remote-service' "$LOG_FILE" >/dev/null

# Native package paths may carry their own explicit service contract.
: > "$LOG_FILE"
plan_native=$(plan_native_package native-fixture opensuse-leap zypper)
printf '%s\n' "$plan_native" | grep 'native-package' >/dev/null
install_native_package native-fixture opensuse-leap zypper
grep 'install_packages zypper native-package' "$LOG_FILE" >/dev/null
grep 'systemctl enable --now native-service' "$LOG_FILE" >/dev/null

# Fingerprint mismatch is a hard fail before mutation.
BAD_MANIFEST="$TEST_ROOT/bad-fingerprint.json"
jq '.repositories.remote.targets["platform:fedora"].keys[0].fingerprint = "BBBB BBBB BBBB BBBB BBBB BBBB BBBB BBBB BBBB BBBB"' "$REPOSITORY_MANIFEST" > "$BAD_MANIFEST"
REPOSITORY_MANIFEST="$BAD_MANIFEST"
export REPOSITORY_MANIFEST
rm -f "$TEST_ROOT/etc/yum.repos.d/remote.repo" "$TEST_ROOT/etc/pki/rpm-gpg/remote.gpg"
: > "$LOG_FILE"
if install_vendor_repository remote fedora fedora dnf amd64 44 >/dev/null 2>&1; then
  echo "repository key fingerprint mismatch unexpectedly accepted" >&2
  exit 1
fi
[ ! -s "$LOG_FILE" ] || { echo "mutation occurred after fingerprint mismatch" >&2; exit 1; }
REPOSITORY_MANIFEST="$TEST_ROOT/repositories.json"
export REPOSITORY_MANIFEST

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

printf 'repository v2 helper tests passed\n'

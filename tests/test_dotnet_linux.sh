#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-dotnet-test.XXXXXX")
cleanup_test_root() {
  find "$TEST_ROOT" -type l -delete 2>/dev/null || true
  find "$TEST_ROOT" -type f -delete 2>/dev/null || true
  find "$TEST_ROOT" -depth -type d -exec rmdir {} \; 2>/dev/null || true
}
trap 'cleanup_test_root' EXIT HUP INT TERM
STATE_DIR="$TEST_ROOT/state"
BIN_DIR="$TEST_ROOT/bin"
mkdir -p "$STATE_DIR" "$BIN_DIR" "$TEST_ROOT/etc/apt" "$TEST_ROOT/keys"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }
log() { :; }
die() { echo "$*" >&2; exit 1; }
sha256_file() { sha256sum "$1" | awk '{print $1}'; }

MUTATION_LOG="$TEST_ROOT/mutations.log"
PACKAGE_LOG="$TEST_ROOT/packages.log"
PM_LOG="$TEST_ROOT/package-managers.log"

privileged() {
  printf '%s\n' "$*" >> "$MUTATION_LOG"
  _test_cmd=$1
  shift
  case "$_test_cmd" in
    install) command install "$@" ;;
    apt-get|rpm|zypper) return 0 ;;
    *) return 0 ;;
  esac
}

install_packages() {
  _test_pm=$1
  shift
  printf '%s\n' "$_test_pm" >> "$PM_LOG"
  printf '%s\n' "$*" >> "$PACKAGE_LOG"
  cat > "$BIN_DIR/dotnet" <<'EOF'
#!/bin/sh
case "$1" in
  --list-sdks) printf '10.0.110 [/fixture/sdk]\n' ;;
  --info) printf '.NET SDK fixture\n' ;;
  *) exit 0 ;;
esac
EOF
  chmod 0755 "$BIN_DIR/dotnet"
}

download_https() {
  url=$1
  dest=$2
  case "$url" in
    https://packages.microsoft.com/keys/microsoft.asc|https://packages.microsoft.com/keys/microsoft-2025.asc)
      printf 'fixture-key\n' > "$dest"
      ;;
    *) echo "unexpected URL: $url" >&2; return 97 ;;
  esac
}

cat > "$BIN_DIR/gpg" <<'EOF'
#!/bin/sh
if printf '%s\n' "$*" | grep -q -- '--show-keys'; then
  printf 'pub:-:4096:1:DEADBEEF:0:0::::::\n'
  printf 'fpr:::::::::%s:\n' "${FAKE_FPR:-BC528686B50D79E339D3721CEB3E94ADBE1229CF}"
  exit 0
fi
out=
in=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) out=$2; shift 2 ;;
    --dearmor|--no-tty|--batch) shift ;;
    *) in=$1; shift ;;
  esac
done
cp "$in" "$out"
EOF
chmod 0755 "$BIN_DIR/gpg"

cat > "$BIN_DIR/subscription-manager" <<'EOF'
#!/bin/sh
[ "${RHEL_REGISTERED:-1}" = 1 ] || exit 1
[ "$1" = identity ] && exit 0
exit 0
EOF
chmod 0755 "$BIN_DIR/subscription-manager"

PATH="$BIN_DIR:$PATH"
export PATH STATE_DIR

DOTNET_LINUX_MANIFEST="$TEST_ROOT/dotnet-linux.json"
export DOTNET_LINUX_MANIFEST
cat > "$DOTNET_LINUX_MANIFEST" <<EOF
{
  "schema_version": 1,
  "sdk_major": "10.0",
  "support": "experimental",
  "targets": {
    "debian": {
      "documentation": "https://learn.microsoft.com/en-us/dotnet/core/install/linux-debian",
      "package_manager": "apt",
      "package_source": "microsoft",
      "sdk_package": "dotnet-sdk-10.0",
      "versions": {
        "12": {"architectures":["amd64","arm64"],"repository":{"base_url":"https://packages.microsoft.com/debian/12/prod","suite":"bookworm","key_url":"https://packages.microsoft.com/keys/microsoft.asc","key_fingerprint":"BC52 8686 B50D 79E3 39D3 721C EB3E 94AD BE12 29CF","key_destination":"$TEST_ROOT/keys/microsoft-prod.gpg","repository_file":"$TEST_ROOT/etc/apt/microsoft-prod.list"}},
        "13": {"architectures":["amd64","arm64"],"repository":{"base_url":"https://packages.microsoft.com/debian/13/prod","suite":"trixie","key_url":"https://packages.microsoft.com/keys/microsoft-2025.asc","key_fingerprint":"AA86 F75E 427A 19DD 3334 6403 EE4D 7792 F748 182B","key_destination":"$TEST_ROOT/keys/microsoft-prod.gpg","repository_file":"$TEST_ROOT/etc/apt/microsoft-prod.list"}}
      }
    },
    "fedora": {"documentation":"https://learn.microsoft.com/en-us/dotnet/core/install/linux-fedora","package_manager":"dnf","package_source":"distribution","sdk_package":"dotnet-sdk-10.0","versions":{"43":{"architectures":["amd64"]},"44":{"architectures":["amd64"]}}},
    "rhel": {"documentation":"https://learn.microsoft.com/en-us/dotnet/core/install/linux-rhel","package_manager":"dnf","package_source":"distribution-appstream","sdk_package":"dotnet-sdk-10.0","subscription_required":true,"versions":{"8":{"architectures":["amd64","arm64","s390x","ppc64le"]},"9":{"architectures":["amd64","arm64","s390x","ppc64le"]},"10":{"architectures":["amd64","arm64","s390x","ppc64le"]}}},
    "opensuse-leap": {"documentation":"https://learn.microsoft.com/en-us/dotnet/core/install/linux-opensuse","package_manager":"zypper","package_source":"microsoft","sdk_package":"dotnet-sdk-10.0","versions":{"16":{"architectures":["amd64","arm64"],"repository":{"base_url":"https://packages.microsoft.com/opensuse/16/prod/","key_url":"https://packages.microsoft.com/keys/microsoft.asc","key_fingerprint":"BC52 8686 B50D 79E3 39D3 721C EB3E 94AD BE12 29CF","key_destination":"$TEST_ROOT/keys/microsoft-prod.gpg","repository_file":"$TEST_ROOT/etc/zypp/microsoft-prod.repo","repository_id":"packages-microsoft-com-prod"}}}}
  }
}
EOF

# shellcheck source=../lib/dotnet-linux.sh
. "$ROOT/lib/dotnet-linux.sh"

dotnet_linux_validate_target debian 12 amd64 apt
dotnet_linux_validate_target debian 13 arm64 apt
dotnet_linux_validate_target fedora 44 amd64 dnf
dotnet_linux_validate_target rhel 10 ppc64le dnf
dotnet_linux_validate_target opensuse-leap 16 arm64 zypper
if (dotnet_linux_validate_target debian 11 amd64 apt >/dev/null 2>&1); then echo "Debian 11 unexpectedly supported" >&2; exit 1; fi
if (dotnet_linux_validate_target fedora 44 arm64 dnf >/dev/null 2>&1); then echo "unvalidated Fedora arm64 unexpectedly supported" >&2; exit 1; fi
if (dotnet_linux_validate_target opensuse-leap 15 amd64 zypper >/dev/null 2>&1); then echo "Leap 15 unexpectedly supported" >&2; exit 1; fi

plan=$(dotnet_linux_plan debian 12 amd64 apt)
printf '%s\n' "$plan" | grep 'package_source: microsoft' >/dev/null
printf '%s\n' "$plan" | grep 'mutates_host: false' >/dev/null
printf '%s\n' "$plan" | grep 'BC52 8686' >/dev/null

: > "$MUTATION_LOG"
: > "$PACKAGE_LOG"
: > "$PM_LOG"
rm -f "$BIN_DIR/dotnet"
dotnet_linux_install debian 12 amd64 apt
[ -f "$TEST_ROOT/keys/microsoft-prod.gpg" ]
[ -f "$TEST_ROOT/etc/apt/microsoft-prod.list" ]
grep 'https://packages.microsoft.com/debian/12/prod bookworm main' "$TEST_ROOT/etc/apt/microsoft-prod.list" >/dev/null
grep '^apt$' "$PM_LOG" >/dev/null
grep '^dotnet-sdk-10.0$' "$PACKAGE_LOG" >/dev/null
[ "$(tail -n 1 "$STATE_DIR/dotnet-linux.jsonl" | jq -r '.action')" = installed-verified ]

lines_before=$(wc -l < "$PACKAGE_LOG")
dotnet_linux_install debian 12 amd64 apt
[ "$(wc -l < "$PACKAGE_LOG")" -eq "$lines_before" ]
[ "$(tail -n 1 "$STATE_DIR/dotnet-linux.jsonl" | jq -r '.action')" = observed-existing ]

rm -f "$BIN_DIR/dotnet"
printf 'foreign repository\n' > "$TEST_ROOT/etc/apt/microsoft-prod.list"
: > "$PACKAGE_LOG"
if (dotnet_linux_install debian 12 amd64 apt >/dev/null 2>&1); then echo "foreign repo unexpectedly overwritten" >&2; exit 1; fi
[ ! -s "$PACKAGE_LOG" ]
rm -f "$TEST_ROOT/etc/apt/microsoft-prod.list" "$TEST_ROOT/keys/microsoft-prod.gpg"

FAKE_FPR=0000000000000000000000000000000000000000
export FAKE_FPR
: > "$MUTATION_LOG"
if (dotnet_linux_install debian 12 amd64 apt >/dev/null 2>&1); then echo "fingerprint mismatch unexpectedly accepted" >&2; exit 1; fi
[ ! -s "$MUTATION_LOG" ]
unset FAKE_FPR

rm -f "$BIN_DIR/dotnet"
: > "$PACKAGE_LOG"
: > "$PM_LOG"
dotnet_linux_install fedora 44 amd64 dnf
grep '^dnf$' "$PM_LOG" >/dev/null
grep '^dotnet-sdk-10.0$' "$PACKAGE_LOG" >/dev/null

rm -f "$BIN_DIR/dotnet"
RHEL_REGISTERED=0
export RHEL_REGISTERED
: > "$PACKAGE_LOG"
if (dotnet_linux_install rhel 10 amd64 dnf >/dev/null 2>&1); then echo "unregistered RHEL unexpectedly accepted" >&2; exit 1; fi
[ ! -s "$PACKAGE_LOG" ]
RHEL_REGISTERED=1
export RHEL_REGISTERED
: > "$PM_LOG"
dotnet_linux_install rhel 10 amd64 dnf
grep '^dnf$' "$PM_LOG" >/dev/null
grep '^dotnet-sdk-10.0$' "$PACKAGE_LOG" >/dev/null

rm -f "$STATE_DIR/dotnet-linux.jsonl"
printf '{}\n' > "$TEST_ROOT/state-target"
ln -s "$TEST_ROOT/state-target" "$STATE_DIR/dotnet-linux.jsonl"
if (_dotnet_state_ready >/dev/null 2>&1); then echo "state symlink unexpectedly accepted" >&2; exit 1; fi

echo ".NET Linux adapter offline tests passed"

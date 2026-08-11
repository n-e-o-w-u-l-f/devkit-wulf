#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-flutter-selector.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' 0 1 2 15
HOME="$TMP_ROOT/home with spaces"
export HOME
mkdir -p "$HOME/develop/flutter/bin"

fail() { printf '%s\n' "fixture failure: $*" >&2; exit 1; }
die() { fail "$*"; }
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'
  fi
}

cat > "$HOME/develop/flutter/bin/flutter" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] || exit 2
printf '%s\n' 'Flutter 9.9.9 test'
EOF
cat > "$HOME/develop/flutter/bin/dart" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] || exit 2
printf '%s\n' 'Dart SDK version: 9.9.9 test'
EOF
chmod +x "$HOME/develop/flutter/bin/flutter" "$HOME/develop/flutter/bin/dart"

flutter_sha=$(sha256_file "$HOME/develop/flutter/bin/flutter")
dart_sha=$(sha256_file "$HOME/develop/flutter/bin/dart")
cat > "$HOME/develop/flutter/.devkit-wulf-artifact.json" <<EOF
{"environment":"flutter","version":"9.9.9","source_url":"https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_9.9.9-stable.tar.xz","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","critical_files":{"bin/flutter":"$flutter_sha","bin/dart":"$dart_sha"}}
EOF

# shellcheck source=../lib/flutter-posix-environment.sh
. "$ROOT_DIR/lib/flutter-posix-environment.sh"

verify_flutter_stable_managed linux || fail "valid Linux managed fixture did not verify"
if verify_flutter_stable_managed macos; then fail "Linux marker incorrectly verified as macOS"; fi

printf '%s\n' '# tamper' >> "$HOME/develop/flutter/bin/flutter"
if verify_flutter_stable_managed linux; then fail "tampered Flutter launcher incorrectly verified"; fi

# Restore a valid launcher/hash then prove a symlinked bin parent is rejected.
cat > "$HOME/develop/flutter/bin/flutter" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] || exit 2
printf '%s\n' 'Flutter 9.9.9 test'
EOF
chmod +x "$HOME/develop/flutter/bin/flutter"
flutter_sha=$(sha256_file "$HOME/develop/flutter/bin/flutter")
jq --arg f "$flutter_sha" '.critical_files["bin/flutter"]=$f' "$HOME/develop/flutter/.devkit-wulf-artifact.json" > "$HOME/develop/flutter/.marker.tmp"
mv "$HOME/develop/flutter/.marker.tmp" "$HOME/develop/flutter/.devkit-wulf-artifact.json"
verify_flutter_stable_managed linux || fail "restored fixture did not verify"

mv "$HOME/develop/flutter/bin" "$HOME/develop/flutter/bin.real"
ln -s "$HOME/develop/flutter/bin.real" "$HOME/develop/flutter/bin"
if verify_flutter_stable_managed linux; then fail "symlinked bin directory incorrectly verified"; fi

printf '%s\n' 'Flutter POSIX selector fixture: OK'

#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

log() { printf '%s\n' "[devkit-wulf bootstrap] $*"; }
die() { printf '%s\n' "[devkit-wulf bootstrap] ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[ "$(uname -s)" = Darwin ] || die "bootstrap/macos.sh is for macOS"

if ! xcode-select -p >/dev/null 2>&1; then
  log "Xcode Command Line Tools are required. Launching Apple's installer request."
  xcode-select --install
  die "complete the Xcode Command Line Tools installation, then rerun this bootstrap"
fi

if ! have brew; then
  cat >&2 <<'EOF'
[devkit-wulf bootstrap] Homebrew is not installed.
The orchestrator does not silently pipe the Homebrew installer into a shell.
Install Homebrew from its official documentation, or explicitly opt into the
reviewed bootstrap path with:

  DEVKIT_WULF_ACCEPT_HOMEBREW_SCRIPT=1 ./bootstrap/macos.sh
EOF
  [ "${DEVKIT_WULF_ACCEPT_HOMEBREW_SCRIPT:-0}" = 1 ] || exit 1
  tmp=${TMPDIR:-/tmp}/devkit-wulf-homebrew-$$.sh
  trap 'rm -f "$tmp"' EXIT HUP INT TERM
  /usr/bin/curl --fail --location --proto '=https' --tlsv1.2 -o "$tmp" https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
  [ -s "$tmp" ] || die "Homebrew installer download is empty"
  if grep -Eiq 'rm[[:space:]]+-rf[[:space:]]+/(($)|[[:space:]])|mkfs|dd[[:space:]].*of=/dev/' "$tmp"; then
    die "GATE-06 blocked Homebrew installer due to destructive pattern"
  fi
  hash=$(/usr/bin/shasum -a 256 "$tmp" | awk '{print $1}')
  log "Downloaded official Homebrew installer SHA-256: $hash"
  /bin/bash "$tmp"
  rm -f "$tmp"; trap - EXIT HUP INT TERM
fi

if ! have jq; then brew install jq; fi
if ! have curl; then die "curl unexpectedly unavailable on macOS"; fi

chmod +x "$ROOT_DIR/bin/devkit-wulf" 2>/dev/null || true
"$ROOT_DIR/bin/devkit-wulf" doctor

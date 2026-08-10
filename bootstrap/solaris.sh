#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

log() { printf '%s\n' "[devkit-wulf bootstrap] $*"; }
die() { printf '%s\n' "[devkit-wulf bootstrap] ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
privileged() { if [ "$(id -u)" -eq 0 ]; then "$@"; elif have pfexec; then pfexec "$@"; elif have sudo; then sudo "$@"; else die "privilege required for: $*"; fi; }

[ "$(uname -s)" = SunOS ] || die "bootstrap/solaris.sh is for Solaris/illumos hosts"

if ! have jq; then
  if have pkg; then
    privileged pkg install jq curl || die "pkg could not install jq/curl; package names vary by Solaris/illumos distribution and are not guessed"
  else
    die "no IPS pkg command found; install jq and an HTTPS download client using the host's authoritative package system"
  fi
fi

chmod +x "$ROOT_DIR/bin/devkit-wulf" 2>/dev/null || true
"$ROOT_DIR/bin/devkit-wulf" doctor
log "Solaris/illumos remains an authoritative-target validation tier; no support promotion occurs from bootstrap success alone."

#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

log() { printf '%s\n' "[devkit-wulf bootstrap] $*"; }
die() { printf '%s\n' "[devkit-wulf bootstrap] ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
privileged() { if [ "$(id -u)" -eq 0 ]; then "$@"; elif have sudo; then sudo "$@"; else die "privilege required for: $*"; fi; }

[ "$(uname -s)" = AIX ] || die "bootstrap/aix.sh is for AIX"

if ! have jq; then
  if have dnf; then
    privileged dnf install -y jq curl
  elif have yum; then
    privileged yum install -y jq curl
  else
    die "AIX Toolbox package management was not detected. Install jq and curl from an authoritative AIX source; devkit-wulf will not guess a repository."
  fi
fi

chmod +x "$ROOT_DIR/bin/devkit-wulf" 2>/dev/null || true
"$ROOT_DIR/bin/devkit-wulf" doctor
log "AIX remains an authoritative-target validation tier; bootstrap success does not promote environment support."

#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

log() { printf '%s\n' "[devkit-wulf bootstrap] $*"; }
die() { printf '%s\n' "[devkit-wulf bootstrap] ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
privileged() { if [ "$(id -u)" -eq 0 ]; then "$@"; elif have sudo; then sudo "$@"; elif have doas; then doas "$@"; else die "privilege required for: $*"; fi; }

[ "$(uname -s)" = Linux ] || die "bootstrap/linux.sh is for Linux and WSL2 Linux distributions"

if have jq; then
  log "jq already available: $(jq --version)"
else
  if have apt-get; then
    privileged apt-get update
    privileged apt-get install -y jq ca-certificates curl
  elif have pacman; then
    privileged pacman -S --needed --noconfirm jq ca-certificates curl
  elif have dnf; then
    privileged dnf install -y jq ca-certificates curl
  elif have zypper; then
    privileged zypper --non-interactive install jq ca-certificates curl
  elif have apk; then
    privileged apk add jq ca-certificates curl
  else
    die "no supported Linux package manager found; install jq and an HTTPS download client manually"
  fi
fi

chmod +x "$ROOT_DIR/bin/devkit-wulf" 2>/dev/null || true
"$ROOT_DIR/bin/devkit-wulf" doctor

if [ -n "${WSL_INTEROP:-}" ] || grep -Eqi 'microsoft|wsl' /proc/version 2>/dev/null; then
  log "WSL detected. Keep Linux-tool projects in the WSL filesystem for the normal fast path."
fi

#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

log() { printf '%s\n' "[devkit-wulf bootstrap] $*"; }
die() { printf '%s\n' "[devkit-wulf bootstrap] ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
privileged() { if [ "$(id -u)" -eq 0 ]; then "$@"; elif have doas; then doas "$@"; elif have sudo; then sudo "$@"; else die "privilege required for: $*"; fi; }

case "$(uname -s)" in FreeBSD|OpenBSD|NetBSD|DragonFly) ;; *) die "bootstrap/bsd.sh is for BSD hosts" ;; esac

if ! have jq; then
  if have pkg; then privileged pkg install -y jq curl
  elif have pkg_add; then privileged pkg_add jq curl
  elif have pkgin; then privileged pkgin -y install jq curl
  else die "no supported BSD package manager detected; install jq and curl manually"; fi
fi

chmod +x "$ROOT_DIR/bin/devkit-wulf" 2>/dev/null || true
"$ROOT_DIR/bin/devkit-wulf" doctor
log "BSD support remains experimental until target-specific CI/host validation passes."

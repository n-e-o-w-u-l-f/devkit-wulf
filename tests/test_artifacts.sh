#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ARTIFACT_MANIFEST="$ROOT/manifests/artifacts.json"
STATE_DIR=${TMPDIR:-/tmp}/devkit-wulf-artifact-test-state-$$
trap 'rm -rf "$STATE_DIR"' EXIT HUP INT TERM

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

# Minimal caller contract needed by pure helper functions.
have() { command -v "$1" >/dev/null 2>&1; }
log() { :; }
warn() { :; }
die() { echo "$*" >&2; exit 1; }
# These are not called by the pure helper assertions below.
download_https() { return 99; }
sha256_file() { return 99; }
privileged() { "$@"; }

# shellcheck source=../lib/artifacts.sh
. "$ROOT/lib/artifacts.sh"

artifact_definition_exists kubectl

target=$(artifact_target_json kubectl debian debian amd64)
[ "$(printf '%s' "$target" | jq -r '.destination')" = /usr/local/bin/kubectl ]
[ "$(printf '%s' "$target" | jq -r '.integrity')" = sha256 ]
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

echo "artifact helper tests passed"

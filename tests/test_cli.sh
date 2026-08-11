#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CLI="$ROOT/bin/devkit-wulf"
TMP_STATE=${TMPDIR:-/tmp}/devkit-wulf-test-state-$$
PROFILE_LOG=${TMPDIR:-/tmp}/devkit-wulf-profile-test-$$.log
trap 'rm -rf "$TMP_STATE" "$PROFILE_LOG"' EXIT HUP INT TERM
export DEVKIT_WULF_STATE_DIR="$TMP_STATE"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

sh "$CLI" detect | grep '^platform='
sh "$CLI" list | grep '^base'
sh "$CLI" plan base | grep '^mutates_host=false$'
sh "$CLI" plan go | grep '^environment=go$'
sh "$CLI" doctor | grep 'repository manifest JSON parse: PASS'
sh "$CLI" doctor | grep 'doctor completed'

# Repository/native-package metadata may resolve a safer effective strategy without
# changing the experimental support status in environments.json.
sh "$CLI" list --platform fedora | grep -E '^opentofu[[:space:]]+experimental[[:space:]]+package-manager$'
sh "$CLI" list --platform debian | grep -E '^opentofu[[:space:]]+experimental[[:space:]]+vendor-repository$'
sh "$CLI" list --platform rhel | grep -E '^opentofu[[:space:]]+experimental[[:space:]]+vendor-repository$'
sh "$CLI" list --platform opensuse-leap | grep -E '^opentofu[[:space:]]+experimental[[:space:]]+vendor-repository$'

# Docker vendor repositories are exact-platform contracts. Do not implicitly
# extend Docker's upstream-tested distro claims to derivatives.
sh "$CLI" list --platform debian | grep -E '^docker[[:space:]]+experimental[[:space:]]+vendor-repository$'
sh "$CLI" list --platform ubuntu | grep -E '^docker[[:space:]]+experimental[[:space:]]+vendor-repository$'
sh "$CLI" list --platform fedora | grep -E '^docker[[:space:]]+experimental[[:space:]]+vendor-repository$'
sh "$CLI" list --platform rhel | grep -E '^docker[[:space:]]+experimental[[:space:]]+vendor-repository$'
sh "$CLI" list --platform opensuse-leap | grep -E '^docker[[:space:]]+experimental[[:space:]]+package-manager$'
sh "$CLI" list --platform opensuse-tumbleweed | grep -E '^docker[[:space:]]+experimental[[:space:]]+package-manager$'
sh "$CLI" list --platform linuxmint | grep -E '^docker[[:space:]]+experimental[[:space:]]+manual$'
sh "$CLI" list --platform rocky | grep -E '^docker[[:space:]]+experimental[[:space:]]+manual$'
sh "$CLI" list --platform almalinux | grep -E '^docker[[:space:]]+experimental[[:space:]]+manual$'

if sh "$CLI" plan definitely-not-an-environment >/dev/null 2>&1; then
  echo "unknown environment unexpectedly succeeded" >&2
  exit 1
fi

if sh "$CLI" remove base >/dev/null 2>&1; then
  echo "unsafe remove unexpectedly succeeded" >&2
  exit 1
fi

# Profiles must not auto-install experimental entries without explicit opt-in.
# Refusal is acceptable in the pre-1.0 catalog; mutation is not.
if sh "$CLI" install profile:full >"$PROFILE_LOG" 2>&1; then
  :
fi
if [ -s "$TMP_STATE/state.jsonl" ] 2>/dev/null; then
  echo "profile:full mutated state without experimental opt-in" >&2
  cat "$PROFILE_LOG" >&2
  exit 1
fi

echo "POSIX CLI smoke tests passed"

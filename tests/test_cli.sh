#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CLI="$ROOT/bin/devkit-wulf"
TMP_STATE=${TMPDIR:-/tmp}/devkit-wulf-test-state-$$
trap 'rm -rf "$TMP_STATE"' EXIT HUP INT TERM
export DEVKIT_WULF_STATE_DIR="$TMP_STATE"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

sh "$CLI" detect | grep '^platform='
sh "$CLI" list | grep '^base'
sh "$CLI" plan base | grep '^mutates_host=false$'
sh "$CLI" plan go | grep '^environment=go$'
sh "$CLI" doctor | grep 'doctor completed'

if sh "$CLI" plan definitely-not-an-environment >/dev/null 2>&1; then
  echo "unknown environment unexpectedly succeeded" >&2
  exit 1
fi

if sh "$CLI" remove base >/dev/null 2>&1; then
  echo "unsafe remove unexpectedly succeeded" >&2
  exit 1
fi

# Profiles must not auto-install experimental entries without explicit opt-in.
# This command is expected to perform no package-manager mutation and exit cleanly.
sh "$CLI" install profile:full >/tmp/devkit-wulf-profile-test-$$.log 2>&1
if [ -s "$STATE_FILE" ] 2>/dev/null; then
  echo "profile:full mutated state without experimental opt-in" >&2
  cat /tmp/devkit-wulf-profile-test-$$.log >&2
  exit 1
fi
rm -f /tmp/devkit-wulf-profile-test-$$.log

echo "POSIX CLI smoke tests passed"

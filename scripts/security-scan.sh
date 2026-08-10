#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FAIL=0

scan_for() {
  pattern=$1 label=$2
  shift 2
  if grep -ERn -- "$pattern" "$@"; then
    echo "SECURITY SCAN FAIL: $label" >&2
    FAIL=1
  fi
}

# Scan executable implementation, not documentation that intentionally discusses forbidden examples.
TARGETS="$ROOT/bin $ROOT/bootstrap"

scan_for 'curl[^\n|]*\|[[:space:]]*(sh|bash|zsh)' 'direct curl-to-shell execution' $TARGETS
scan_for '(irm|Invoke-RestMethod)[^\n|]*\|[[:space:]]*(iex|Invoke-Expression)' 'direct PowerShell download-to-execution' $TARGETS
scan_for 'rm[[:space:]]+-rf[[:space:]]+/([[:space:]]|$)' 'recursive root deletion' $TARGETS
scan_for '(mkfs|fdisk|parted)[[:space:]]' 'disk/partition mutation' $TARGETS
scan_for '(-SkipCertificateCheck|--insecure|-k[[:space:]]+https://)' 'TLS verification bypass' $TARGETS
scan_for '(--skip-verify|skip_verify)' 'integrity verification bypass' $TARGETS
scan_for 'Set-ExecutionPolicy[^\n]*(LocalMachine|CurrentUser)' 'persistent PowerShell execution-policy weakening' $TARGETS

if [ "$FAIL" -ne 0 ]; then exit 1; fi
echo "security policy scan passed"

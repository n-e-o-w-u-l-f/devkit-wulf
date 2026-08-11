#!/bin/sh
# .NET 10 Linux adapter. Caller provides: jq, have, die, log, privileged,
# install_packages, download_https, sha256_file, STATE_DIR.

DOTNET_LINUX_MANIFEST=${DOTNET_LINUX_MANIFEST:-}

_dotnet_manifest_required() {
  [ -n "$DOTNET_LINUX_MANIFEST" ] || die "DOTNET_LINUX_MANIFEST is not configured"
  [ -f "$DOTNET_LINUX_MANIFEST" ] || die "missing .NET Linux manifest: $DOTNET_LINUX_MANIFEST"
}

dotnet_linux_target_json() {
  _dw_dotnet_platform=$1
  _dotnet_manifest_required
  jq -c --arg p "$_dw_dotnet_platform" '.targets[$p] // empty' "$DOTNET_LINUX_MANIFEST"
}

dotnet_linux_version_json() {
  _dw_dotnet_platform=$1
  _dw_dotnet_version=$2
  _dotnet_manifest_required
  jq -c --arg p "$_dw_dotnet_platform" --arg v "$_dw_dotnet_version" '.targets[$p].versions[$v] // empty' "$DOTNET_LINUX_MANIFEST"
}

dotnet_linux_validate_target() {
  _dw_dotnet_platform=$1
  _dw_dotnet_version=$2
  _dw_dotnet_arch=$3
  _dw_dotnet_pm=$4
  _dw_dotnet_target=$(dotnet_linux_target_json "$_dw_dotnet_platform")
  [ -n "$_dw_dotnet_target" ] || die "GATE-02 .NET 10 has no exact target for $_dw_dotnet_platform"
  _dw_dotnet_entry=$(dotnet_linux_version_json "$_dw_dotnet_platform" "$_dw_dotnet_version")
  [ -n "$_dw_dotnet_entry" ] || die "GATE-02/03 .NET 10 does not support $_dw_dotnet_platform/$_dw_dotnet_version"
  _dw_dotnet_expected_pm=$(printf '%s' "$_dw_dotnet_target" | jq -r '.package_manager')
  [ "$_dw_dotnet_pm" = "$_dw_dotnet_expected_pm" ] || die "GATE-02 .NET target requires $_dw_dotnet_expected_pm, detected $_dw_dotnet_pm"
  printf '%s' "$_dw_dotnet_entry" | jq -e --arg a "$_dw_dotnet_arch" '.architectures | index($a) != null' >/dev/null || \
    die "GATE-02/03 .NET 10 does not support $_dw_dotnet_platform/$_dw_dotnet_version/$_dw_dotnet_arch"
}

_dotnet_normalize_fingerprint() {
  printf '%s' "$1" | tr -d '[:space:]' | tr 'a-f' 'A-F'
}

_dotnet_gpg_command() {
  if have gpg; then printf gpg; elif have gpg2; then printf gpg2; else return 1; fi
}

_dotnet_stage_key() {
  _dw_dotnet_repo=$1
  _dw_dotnet_tmp=$2
  _dw_dotnet_url=$(printf '%s' "$_dw_dotnet_repo" | jq -r '.key_url')
  _dw_dotnet_expected=$(printf '%s' "$_dw_dotnet_repo" | jq -r '.key_fingerprint')
  _dw_dotnet_raw="$_dw_dotnet_tmp/microsoft.asc"
  _dw_dotnet_key="$_dw_dotnet_tmp/microsoft.gpg"
  download_https "$_dw_dotnet_url" "$_dw_dotnet_raw"
  [ -s "$_dw_dotnet_raw" ] || die "GATE-04 downloaded empty Microsoft signing key"
  _dw_dotnet_gpg=$(_dotnet_gpg_command) || die "GATE-05 requires GnuPG before repository mutation"
  _dw_dotnet_actual=$("$_dw_dotnet_gpg" --no-tty --batch --with-colons --show-keys "$_dw_dotnet_raw" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  [ -n "$_dw_dotnet_actual" ] || die "GATE-05 rejected invalid Microsoft OpenPGP key"
  [ "$(_dotnet_normalize_fingerprint "$_dw_dotnet_actual")" = "$(_dotnet_normalize_fingerprint "$_dw_dotnet_expected")" ] || \
    die "GATE-05 Microsoft signing-key fingerprint mismatch"
  "$_dw_dotnet_gpg" --no-tty --batch --dearmor --output "$_dw_dotnet_key" "$_dw_dotnet_raw" || die "GATE-05 failed to dearmor Microsoft key"
  printf '%s' "$_dw_dotnet_key"
}

_dotnet_arch_for_repo() {
  case "$1" in
    amd64) printf amd64 ;;
    arm64) printf arm64 ;;
    *) die "repository architecture cannot be represented safely: $1" ;;
  esac
}

_dotnet_repository_content() {
  _dw_dotnet_platform=$1
  _dw_dotnet_arch=$2
  _dw_dotnet_repo=$3
  _dw_dotnet_base=$(printf '%s' "$_dw_dotnet_repo" | jq -r '.base_url')
  _dw_dotnet_keydest=$(printf '%s' "$_dw_dotnet_repo" | jq -r '.key_destination')
  case "$_dw_dotnet_platform" in
    debian)
      _dw_dotnet_suite=$(printf '%s' "$_dw_dotnet_repo" | jq -r '.suite')
      _dw_dotnet_repoarch=$(_dotnet_arch_for_repo "$_dw_dotnet_arch")
      printf 'deb [arch=%s signed-by=%s] %s %s main\n' "$_dw_dotnet_repoarch" "$_dw_dotnet_keydest" "$_dw_dotnet_base" "$_dw_dotnet_suite"
      ;;
    opensuse-leap)
      _dw_dotnet_id=$(printf '%s' "$_dw_dotnet_repo" | jq -r '.repository_id')
      printf '[%s]\nname=Microsoft Production - openSUSE Leap\nbaseurl=%s\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file://%s\nsslverify=1\n' \
        "$_dw_dotnet_id" "$_dw_dotnet_base" "$_dw_dotnet_keydest"
      ;;
    *) die "no vendor repository renderer for $_dw_dotnet_platform" ;;
  esac
}

_dotnet_preflight_file() {
  _dw_dotnet_path=$1
  _dw_dotnet_staged=$2
  [ ! -L "$_dw_dotnet_path" ] || die "GATE-08 refuses symlink path: $_dw_dotnet_path"
  if [ -e "$_dw_dotnet_path" ]; then
    [ -f "$_dw_dotnet_path" ] || die "GATE-08 existing path is not a regular file: $_dw_dotnet_path"
    cmp -s "$_dw_dotnet_path" "$_dw_dotnet_staged" || die "GATE-08 existing file has different content: $_dw_dotnet_path"
  fi
}

_dotnet_state_ready() {
  [ ! -L "$STATE_DIR" ] || die "GATE-10 refuses .NET state-directory symlink: $STATE_DIR"
  mkdir -p "$STATE_DIR" || die "unable to create state directory: $STATE_DIR"
  _dw_dotnet_state="$STATE_DIR/dotnet-linux.jsonl"
  [ ! -L "$_dw_dotnet_state" ] || die "GATE-10 refuses .NET state-file symlink: $_dw_dotnet_state"
  if [ -e "$_dw_dotnet_state" ]; then
    [ -f "$_dw_dotnet_state" ] || die "GATE-10 .NET state path is not a regular file"
    [ -w "$_dw_dotnet_state" ] || die "GATE-10 .NET state file is not writable"
  fi
}

_dotnet_record_state() {
  _dw_dotnet_action=$1
  _dw_dotnet_platform=$2
  _dw_dotnet_version=$3
  _dw_dotnet_arch=$4
  _dw_dotnet_source=$5
  _dotnet_state_ready
  jq -nc \
    --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg action "$_dw_dotnet_action" \
    --arg platform "$_dw_dotnet_platform" \
    --arg version "$_dw_dotnet_version" \
    --arg architecture "$_dw_dotnet_arch" \
    --arg source "$_dw_dotnet_source" \
    '{timestamp:$timestamp,environment:"dotnet",sdk_major:"10.0",action:$action,platform:$platform,version:$version,architecture:$architecture,source:$source}' \
    >> "$STATE_DIR/dotnet-linux.jsonl"
}

dotnet_linux_verify() {
  have dotnet || return 1
  dotnet --list-sdks 2>/dev/null | awk '$1 ~ /^10[.][0-9]+[.]/ {found=1} END {exit found ? 0 : 1}'
}

dotnet_linux_plan() {
  _dw_dotnet_platform=$1
  _dw_dotnet_version=$2
  _dw_dotnet_arch=$3
  _dw_dotnet_pm=$4
  dotnet_linux_validate_target "$_dw_dotnet_platform" "$_dw_dotnet_version" "$_dw_dotnet_arch" "$_dw_dotnet_pm"
  _dw_dotnet_target=$(dotnet_linux_target_json "$_dw_dotnet_platform")
  _dw_dotnet_entry=$(dotnet_linux_version_json "$_dw_dotnet_platform" "$_dw_dotnet_version")
  _dw_dotnet_source=$(printf '%s' "$_dw_dotnet_target" | jq -r '.package_source')
  printf 'dotnet_linux:\n'
  printf '  sdk_major: 10.0\n'
  printf '  support: experimental\n'
  printf '  platform: %s\n' "$_dw_dotnet_platform"
  printf '  version: %s\n' "$_dw_dotnet_version"
  printf '  architecture: %s\n' "$_dw_dotnet_arch"
  printf '  package_manager: %s\n' "$_dw_dotnet_pm"
  printf '  package_source: %s\n' "$_dw_dotnet_source"
  printf '  package: %s\n' "$(printf '%s' "$_dw_dotnet_target" | jq -r '.sdk_package')"
  printf '  documentation: %s\n' "$(printf '%s' "$_dw_dotnet_target" | jq -r '.documentation')"
  if [ "$_dw_dotnet_source" = microsoft ]; then
    _dw_dotnet_repo=$(printf '%s' "$_dw_dotnet_entry" | jq -c '.repository')
    printf '  repository_file: %s\n' "$(printf '%s' "$_dw_dotnet_repo" | jq -r '.repository_file')"
    printf '  repository_base: %s\n' "$(printf '%s' "$_dw_dotnet_repo" | jq -r '.base_url')"
    printf '  key_url: %s\n' "$(printf '%s' "$_dw_dotnet_repo" | jq -r '.key_url')"
    printf '  key_fingerprint: %s\n' "$(printf '%s' "$_dw_dotnet_repo" | jq -r '.key_fingerprint')"
  fi
  printf '  privilege: required-for-package-and-repository-mutation\n'
  printf '  verification: dotnet --list-sdks contains 10.x\n'
  printf '  mutates_host: false\n'
}

_dotnet_cleanup_staging() {
  [ -n "${_dw_dotnet_tmp:-}" ] || return 0
  rm -f \
    "$_dw_dotnet_tmp/microsoft.asc" \
    "$_dw_dotnet_tmp/microsoft.gpg" \
    "$_dw_dotnet_tmp/repository.conf"
  rmdir "$_dw_dotnet_tmp" 2>/dev/null || true
}

_dotnet_install_microsoft_repo() {
  _dw_dotnet_platform=$1
  _dw_dotnet_version=$2
  _dw_dotnet_arch=$3
  _dw_dotnet_target=$4
  _dw_dotnet_entry=$5
  _dw_dotnet_repo=$(printf '%s' "$_dw_dotnet_entry" | jq -c '.repository')
  _dw_dotnet_pm=$(printf '%s' "$_dw_dotnet_target" | jq -r '.package_manager')
  _dw_dotnet_tmp=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-dotnet.XXXXXX") || die "unable to create .NET staging directory"
  trap '_dotnet_cleanup_staging' EXIT HUP INT TERM
  _dw_dotnet_staged_key=$(_dotnet_stage_key "$_dw_dotnet_repo" "$_dw_dotnet_tmp")
  _dw_dotnet_repo_staged="$_dw_dotnet_tmp/repository.conf"
  _dotnet_repository_content "$_dw_dotnet_platform" "$_dw_dotnet_arch" "$_dw_dotnet_repo" > "$_dw_dotnet_repo_staged"
  _dw_dotnet_keydest=$(printf '%s' "$_dw_dotnet_repo" | jq -r '.key_destination')
  _dw_dotnet_repofile=$(printf '%s' "$_dw_dotnet_repo" | jq -r '.repository_file')
  _dotnet_preflight_file "$_dw_dotnet_keydest" "$_dw_dotnet_staged_key"
  _dotnet_preflight_file "$_dw_dotnet_repofile" "$_dw_dotnet_repo_staged"
  _dotnet_record_state mutation-intent "$_dw_dotnet_platform" "$_dw_dotnet_version" "$_dw_dotnet_arch" microsoft
  privileged install -d -m 0755 "$(dirname "$_dw_dotnet_keydest")"
  privileged install -m 0644 "$_dw_dotnet_staged_key" "$_dw_dotnet_keydest"
  privileged install -d -m 0755 "$(dirname "$_dw_dotnet_repofile")"
  privileged install -m 0644 "$_dw_dotnet_repo_staged" "$_dw_dotnet_repofile"
  case "$_dw_dotnet_platform" in
    debian) privileged apt-get update ;;
    opensuse-leap)
      privileged rpm --import "$_dw_dotnet_keydest"
      _dw_dotnet_repoid=$(printf '%s' "$_dw_dotnet_repo" | jq -r '.repository_id')
      privileged zypper --non-interactive --gpg-auto-import-keys refresh "$_dw_dotnet_repoid"
      ;;
  esac
  install_packages "$_dw_dotnet_pm" "$(printf '%s' "$_dw_dotnet_target" | jq -r '.sdk_package')"
  _dotnet_cleanup_staging
  _dw_dotnet_tmp=
  trap - EXIT HUP INT TERM
}

_dotnet_check_distribution_preconditions() {
  _dw_dotnet_platform=$1
  _dw_dotnet_target=$2
  if [ "$_dw_dotnet_platform" = rhel ] && [ "$(printf '%s' "$_dw_dotnet_target" | jq -r '.subscription_required // false')" = true ]; then
    have subscription-manager || die "GATE-02 RHEL .NET requires subscription-manager and a registered RHEL host"
    subscription-manager identity >/dev/null 2>&1 || die "GATE-02 RHEL host is not registered with Subscription Manager"
  fi
}

dotnet_linux_install() {
  _dw_dotnet_platform=$1
  _dw_dotnet_version=$2
  _dw_dotnet_arch=$3
  _dw_dotnet_pm=$4
  dotnet_linux_validate_target "$_dw_dotnet_platform" "$_dw_dotnet_version" "$_dw_dotnet_arch" "$_dw_dotnet_pm"
  _dw_dotnet_target=$(dotnet_linux_target_json "$_dw_dotnet_platform")
  _dw_dotnet_entry=$(dotnet_linux_version_json "$_dw_dotnet_platform" "$_dw_dotnet_version")
  _dw_dotnet_source=$(printf '%s' "$_dw_dotnet_target" | jq -r '.package_source')

  if dotnet_linux_verify; then
    log ".NET 10 SDK already passes verification; no mutation performed"
    _dotnet_record_state observed-existing "$_dw_dotnet_platform" "$_dw_dotnet_version" "$_dw_dotnet_arch" "$_dw_dotnet_source"
    return 0
  fi

  case "$_dw_dotnet_source" in
    microsoft) _dotnet_install_microsoft_repo "$_dw_dotnet_platform" "$_dw_dotnet_version" "$_dw_dotnet_arch" "$_dw_dotnet_target" "$_dw_dotnet_entry" ;;
    distribution|distribution-appstream)
      _dotnet_check_distribution_preconditions "$_dw_dotnet_platform" "$_dw_dotnet_target"
      _dotnet_record_state mutation-intent "$_dw_dotnet_platform" "$_dw_dotnet_version" "$_dw_dotnet_arch" "$_dw_dotnet_source"
      install_packages "$_dw_dotnet_pm" "$(printf '%s' "$_dw_dotnet_target" | jq -r '.sdk_package')"
      ;;
    *) die "unsupported .NET package source: $_dw_dotnet_source" ;;
  esac

  dotnet_linux_verify || die "GATE-12 .NET 10 SDK verification failed after installation"
  _dotnet_record_state installed-verified "$_dw_dotnet_platform" "$_dw_dotnet_version" "$_dw_dotnet_arch" "$_dw_dotnet_source"
}

#!/bin/sh
# Shared verified-artifact adapter for the POSIX orchestrator.
# The caller provides: jq, have, log, warn, die, download_https, sha256_file,
# privileged, ARTIFACT_MANIFEST and STATE_DIR.

artifact_definition_exists() {
  jq -e --arg e "$1" '.artifacts[$e] != null' "$ARTIFACT_MANIFEST" >/dev/null 2>&1
}

artifact_generic_target_key() {
  _dw_art_platform=$1
  _dw_art_family=$2
  case "$_dw_art_family" in
    debian|arch|fedora|rhel|opensuse|alpine) printf 'linux' ;;
    *) printf '%s' "$_dw_art_platform" ;;
  esac
}

artifact_target_json() {
  _dw_art_env=$1
  _dw_art_platform=$2
  _dw_art_family=$3
  _dw_art_arch=$4
  _dw_art_generic=$(artifact_generic_target_key "$_dw_art_platform" "$_dw_art_family")
  jq -c \
    --arg e "$_dw_art_env" \
    --arg p "$_dw_art_platform" \
    --arg f "$_dw_art_family" \
    --arg g "$_dw_art_generic" \
    --arg a "$_dw_art_arch" '
      (.artifacts[$e] // null) as $artifact
      | if $artifact == null then empty else
          ($artifact.targets[$p] // $artifact.targets[$f] // $artifact.targets[$g] // null) as $target
          | if $target == null or ($target.architectures[$a] // null) == null then empty
            else (($target | del(.architectures)) + $target.architectures[$a])
            end
        end
    ' "$ARTIFACT_MANIFEST"
}

artifact_version_resolver_json() {
  jq -c --arg e "$1" '.artifacts[$e].version // empty' "$ARTIFACT_MANIFEST"
}

artifact_validate_version() {
  _dw_art_candidate=$1
  _dw_art_pattern=$2
  [ -n "$_dw_art_candidate" ] || return 1
  case "$_dw_art_candidate" in
    *[!A-Za-z0-9._+-]*) return 1 ;;
  esac
  printf '%s\n' "$_dw_art_candidate" | grep -Eq -- "$_dw_art_pattern"
}

artifact_resolve_version() (
  _dw_art_env=$1
  _dw_art_resolver=$(artifact_version_resolver_json "$_dw_art_env")
  [ -n "$_dw_art_resolver" ] || die "no artifact version resolver for $_dw_art_env"
  _dw_art_kind=$(printf '%s' "$_dw_art_resolver" | jq -r '.resolver')
  _dw_art_url=$(printf '%s' "$_dw_art_resolver" | jq -r '.url')
  _dw_art_pattern=$(printf '%s' "$_dw_art_resolver" | jq -r '.pattern')
  [ "$_dw_art_kind" = text-url ] || die "unsupported artifact version resolver: $_dw_art_kind"
  have mktemp || die "mktemp is required for artifact version resolution"

  _dw_art_tmp=$(mktemp "${TMPDIR:-/tmp}/devkit-wulf-version.XXXXXX") || die "unable to create version resolver staging file"
  trap 'rm -f "$_dw_art_tmp"' EXIT HUP INT TERM
  download_https "$_dw_art_url" "$_dw_art_tmp"
  _dw_art_version=$(tr -d ' \t\r\n' < "$_dw_art_tmp")
  artifact_validate_version "$_dw_art_version" "$_dw_art_pattern" || die "GATE-03 rejected artifact version value from $_dw_art_url"
  printf '%s' "$_dw_art_version"
)

artifact_render_template() {
  _dw_art_template=$1
  _dw_art_version=$2
  artifact_validate_version "$_dw_art_version" '^[A-Za-z0-9][A-Za-z0-9._+-]*$' || return 1
  printf '%s' "$_dw_art_template" | sed "s/{version}/$_dw_art_version/g"
}

artifact_path_ready() {
  _dw_art_dir=$1
  [ -d "$_dw_art_dir" ] || return 1
  case ":${PATH:-}:" in
    *":$_dw_art_dir:"*) return 0 ;;
    *) return 1 ;;
  esac
}

artifact_state_ready() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  [ -d "$STATE_DIR" ] || return 1
  [ -w "$STATE_DIR" ] || return 1
  _dw_art_state_file="$STATE_DIR/artifacts.jsonl"
  [ ! -L "$_dw_art_state_file" ] || return 1
  if [ -e "$_dw_art_state_file" ]; then
    [ -f "$_dw_art_state_file" ] || return 1
    [ -w "$_dw_art_state_file" ] || return 1
  fi
  return 0
}

plan_verified_artifact() {
  _dw_art_env=$1
  _dw_art_platform=$2
  _dw_art_family=$3
  _dw_art_arch=$4
  _dw_art_target=$(artifact_target_json "$_dw_art_env" "$_dw_art_platform" "$_dw_art_family" "$_dw_art_arch")
  [ -n "$_dw_art_target" ] || return 1
  _dw_art_version=$(artifact_resolve_version "$_dw_art_env")
  _dw_art_url_template=$(printf '%s' "$_dw_art_target" | jq -r '.url_template')
  _dw_art_checksum_template=$(printf '%s' "$_dw_art_target" | jq -r '.checksum_url_template')
  _dw_art_url=$(artifact_render_template "$_dw_art_url_template" "$_dw_art_version") || die "invalid artifact URL template/version"
  _dw_art_checksum_url=$(artifact_render_template "$_dw_art_checksum_template" "$_dw_art_version") || die "invalid checksum URL template/version"
  _dw_art_destination=$(printf '%s' "$_dw_art_target" | jq -r '.destination')
  _dw_art_path_dir=$(printf '%s' "$_dw_art_target" | jq -r '.path_directory')
  _dw_art_integrity=$(printf '%s' "$_dw_art_target" | jq -r '.integrity')
  _dw_art_privileged=$(printf '%s' "$_dw_art_target" | jq -r '.privileged')
  _dw_art_publisher=$(jq -r --arg e "$_dw_art_env" '.artifacts[$e].publisher' "$ARTIFACT_MANIFEST")
  _dw_art_version_source=$(jq -r --arg e "$_dw_art_env" '.artifacts[$e].version.url' "$ARTIFACT_MANIFEST")

  printf 'artifact:\n'
  printf '  publisher: %s\n' "$_dw_art_publisher"
  printf '  version_source: %s\n' "$_dw_art_version_source"
  printf '  resolved_version: %s\n' "$_dw_art_version"
  printf '  url: %s\n' "$_dw_art_url"
  printf '  checksum_url: %s\n' "$_dw_art_checksum_url"
  printf '  integrity: %s\n' "$_dw_art_integrity"
  printf '  destination: %s\n' "$_dw_art_destination"
  printf '  path_directory: %s\n' "$_dw_art_path_dir"
  printf '  path_mutation: none\n'
  if [ "$_dw_art_privileged" = true ]; then
    printf '  privilege: root-or-sudo\n'
  else
    printf '  privilege: none\n'
  fi
  printf '  conflict_policy: refuse-existing-different-hash-or-symlink\n'
}

record_artifact_state() {
  _dw_art_env=$1
  _dw_art_version=$2
  _dw_art_url=$3
  _dw_art_checksum_url=$4
  _dw_art_destination=$5
  _dw_art_sha=$6
  _dw_art_action=$7
  _dw_art_created=$8
  artifact_state_ready || die "GATE-10 artifact state path is not safely writable: $STATE_DIR"
  _dw_art_state_file="$STATE_DIR/artifacts.jsonl"
  _dw_art_timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  _dw_art_publisher=$(jq -r --arg e "$_dw_art_env" '.artifacts[$e].publisher' "$ARTIFACT_MANIFEST")
  jq -nc \
    --arg timestamp "$_dw_art_timestamp" \
    --arg environment "$_dw_art_env" \
    --arg publisher "$_dw_art_publisher" \
    --arg version "$_dw_art_version" \
    --arg source_url "$_dw_art_url" \
    --arg checksum_url "$_dw_art_checksum_url" \
    --arg destination "$_dw_art_destination" \
    --arg sha256 "$_dw_art_sha" \
    --arg action "$_dw_art_action" \
    --argjson created "$_dw_art_created" \
    '{timestamp:$timestamp,environment:$environment,publisher:$publisher,version:$version,source_url:$source_url,checksum_url:$checksum_url,destination:$destination,sha256:$sha256,action:$action,created:$created,path_mutation:false}' \
    >> "$_dw_art_state_file"
}

install_verified_artifact() (
  _dw_art_env=$1
  _dw_art_platform=$2
  _dw_art_family=$3
  _dw_art_arch=$4
  _dw_art_target=$(artifact_target_json "$_dw_art_env" "$_dw_art_platform" "$_dw_art_family" "$_dw_art_arch")
  [ -n "$_dw_art_target" ] || die "no verified artifact mapping for $_dw_art_env on $_dw_art_platform/$_dw_art_arch"

  _dw_art_integrity=$(printf '%s' "$_dw_art_target" | jq -r '.integrity')
  [ "$_dw_art_integrity" = sha256 ] || die "unsupported artifact integrity policy: $_dw_art_integrity"
  _dw_art_destination=$(printf '%s' "$_dw_art_target" | jq -r '.destination')
  _dw_art_path_dir=$(printf '%s' "$_dw_art_target" | jq -r '.path_directory')
  _dw_art_mode=$(printf '%s' "$_dw_art_target" | jq -r '.mode')
  _dw_art_privileged=$(printf '%s' "$_dw_art_target" | jq -r '.privileged')
  _dw_art_filename=$(printf '%s' "$_dw_art_target" | jq -r '.filename')

  case "$_dw_art_privileged" in true|false) ;; *) die "invalid artifact privilege metadata for $_dw_art_env" ;; esac
  artifact_path_ready "$_dw_art_path_dir" || die "GATE-13 requires $_dw_art_path_dir to already exist in PATH; devkit-wulf will not modify PATH implicitly"
  artifact_state_ready || die "GATE-10 artifact state path is not safely writable: $STATE_DIR"
  have install || die "POSIX install utility is required for verified binary installation"
  have mktemp || die "mktemp is required for verified binary installation"

  _dw_art_version=$(artifact_resolve_version "$_dw_art_env")
  _dw_art_url=$(artifact_render_template "$(printf '%s' "$_dw_art_target" | jq -r '.url_template')" "$_dw_art_version") || die "invalid artifact URL template/version"
  _dw_art_checksum_url=$(artifact_render_template "$(printf '%s' "$_dw_art_target" | jq -r '.checksum_url_template')" "$_dw_art_version") || die "invalid checksum URL template/version"

  _dw_art_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-artifact.XXXXXX") || die "unable to create artifact staging directory"
  trap 'rm -rf "$_dw_art_tmpdir"' EXIT HUP INT TERM
  _dw_art_payload="$_dw_art_tmpdir/$_dw_art_filename"
  _dw_art_checksum_file="$_dw_art_tmpdir/$_dw_art_filename.sha256"

  download_https "$_dw_art_url" "$_dw_art_payload"
  download_https "$_dw_art_checksum_url" "$_dw_art_checksum_file"

  _dw_art_expected=$(awk 'NR==1 {print $1}' "$_dw_art_checksum_file" | tr 'A-F' 'a-f')
  printf '%s\n' "$_dw_art_expected" | grep -Eq '^[0-9a-f]{64}$' || die "GATE-05 rejected malformed SHA-256 metadata from $_dw_art_checksum_url"
  _dw_art_actual=$(sha256_file "$_dw_art_payload" | tr 'A-F' 'a-f')
  [ "$_dw_art_actual" != unavailable ] || die "GATE-05 requires a local SHA-256 implementation"
  [ "$_dw_art_actual" = "$_dw_art_expected" ] || die "GATE-05 checksum mismatch for $_dw_art_url"

  log "GATE-03 version source: $(jq -r --arg e "$_dw_art_env" '.artifacts[$e].version.url' "$ARTIFACT_MANIFEST") -> $_dw_art_version"
  log "GATE-04 source: $_dw_art_url"
  log "GATE-05 SHA-256 verified: $_dw_art_actual"

  if [ -e "$_dw_art_destination" ] || [ -L "$_dw_art_destination" ]; then
    [ ! -L "$_dw_art_destination" ] || die "GATE-08 conflict: destination is a symbolic link: $_dw_art_destination"
    [ -f "$_dw_art_destination" ] || die "GATE-08 conflict: destination exists and is not a regular file: $_dw_art_destination"
    _dw_art_existing=$(sha256_file "$_dw_art_destination" | tr 'A-F' 'a-f')
    [ "$_dw_art_existing" != unavailable ] || die "GATE-05 requires SHA-256 to evaluate the existing destination"
    if [ "$_dw_art_existing" = "$_dw_art_actual" ]; then
      log "$_dw_art_env exact verified artifact already exists at $_dw_art_destination"
      record_artifact_state "$_dw_art_env" "$_dw_art_version" "$_dw_art_url" "$_dw_art_checksum_url" "$_dw_art_destination" "$_dw_art_actual" observed-exact-artifact false
      exit 0
    fi
    die "GATE-08 conflict: $_dw_art_destination already exists with a different SHA-256; explicit upgrade/migration is required"
  fi

  record_artifact_state "$_dw_art_env" "$_dw_art_version" "$_dw_art_url" "$_dw_art_checksum_url" "$_dw_art_destination" "$_dw_art_actual" mutation-intent false

  if [ "$_dw_art_privileged" = true ]; then
    privileged install -m "$_dw_art_mode" "$_dw_art_payload" "$_dw_art_destination"
  else
    install -m "$_dw_art_mode" "$_dw_art_payload" "$_dw_art_destination"
  fi
  _dw_art_installed=$(sha256_file "$_dw_art_destination" | tr 'A-F' 'a-f')
  [ "$_dw_art_installed" = "$_dw_art_actual" ] || die "GATE-12 installed artifact hash differs from verified staged artifact"

  record_artifact_state "$_dw_art_env" "$_dw_art_version" "$_dw_art_url" "$_dw_art_checksum_url" "$_dw_art_destination" "$_dw_art_actual" installed-verified-artifact true
)

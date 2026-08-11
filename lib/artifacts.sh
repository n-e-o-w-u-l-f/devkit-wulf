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
  [ "$_dw_art_kind" = text-url ] || die "artifact version resolver '$_dw_art_kind' requires target-aware resolution"
  _dw_art_url=$(printf '%s' "$_dw_art_resolver" | jq -r '.url')
  _dw_art_pattern=$(printf '%s' "$_dw_art_resolver" | jq -r '.pattern')
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

artifact_expand_home_path() {
  _dw_art_template=$1
  case "$_dw_art_template" in
    '{home}/'*) ;;
    *) return 1 ;;
  esac
  [ -n "${HOME:-}" ] || return 1
  case "$HOME" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$HOME" in *'\n'*|*'\r'*) return 1 ;; esac
  _dw_art_suffix=${_dw_art_template#\{home\}}
  case "$_dw_art_suffix" in
    *'/../'*|'/..'|*'/..') return 1 ;;
  esac
  printf '%s%s' "$HOME" "$_dw_art_suffix"
}

artifact_path_ready() {
  _dw_art_dir=$1
  [ -d "$_dw_art_dir" ] || return 1
  case ":${PATH:-}:" in
    *":$_dw_art_dir:"*) return 0 ;;
    *) return 1 ;;
  esac
}

artifact_path_declared() {
  _dw_art_dir=$1
  case ":${PATH:-}:" in
    *":$_dw_art_dir:"*) return 0 ;;
    *) return 1 ;;
  esac
}

artifact_state_ready() {
  [ ! -L "$STATE_DIR" ] || return 1
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

artifact_validate_release_archive_path() {
  _dw_art_archive=$1
  [ -n "$_dw_art_archive" ] || return 1
  case "$_dw_art_archive" in
    /*|*'\\'*) return 1 ;;
  esac
  printf '%s\n' "$_dw_art_archive" | awk -F/ '
    {
      for (i = 1; i <= NF; i++) {
        if ($i == "" || $i == "." || $i == "..") exit 1
      }
    }
  '
}

artifact_resolve_release_json() (
  _dw_art_env=$1
  _dw_art_target=$2
  _dw_art_resolver=$(artifact_version_resolver_json "$_dw_art_env")
  [ "$(printf '%s' "$_dw_art_resolver" | jq -r '.resolver')" = release-index ] || die "release-index resolver required for archive artifact"
  _dw_art_channel=$(printf '%s' "$_dw_art_resolver" | jq -r '.channel')
  _dw_art_pattern=$(printf '%s' "$_dw_art_resolver" | jq -r '.version_pattern')
  _dw_art_metadata_url=$(printf '%s' "$_dw_art_target" | jq -r '.release_index_url')
  _dw_art_expected_base=$(printf '%s' "$_dw_art_target" | jq -r '.expected_base_url')
  _dw_art_release_arch=$(printf '%s' "$_dw_art_target" | jq -r '.release_arch')
  have mktemp || die "mktemp is required for release-index resolution"

  _dw_art_tmp=$(mktemp "${TMPDIR:-/tmp}/devkit-wulf-release-index.XXXXXX") || die "unable to create release-index staging file"
  trap 'rm -f "$_dw_art_tmp"' EXIT HUP INT TERM
  download_https "$_dw_art_metadata_url" "$_dw_art_tmp"
  jq -e . "$_dw_art_tmp" >/dev/null 2>&1 || die "GATE-03 release index is not valid JSON: $_dw_art_metadata_url"

  _dw_art_base=$(jq -r '.base_url // empty' "$_dw_art_tmp")
  [ "$_dw_art_base" = "$_dw_art_expected_base" ] || die "GATE-04 release-index base URL differs from expected publisher URL"
  case "$_dw_art_base" in https://*) ;; *) die "GATE-04 release-index base URL is not HTTPS" ;; esac

  _dw_art_current_hash=$(jq -r --arg c "$_dw_art_channel" '.current_release[$c] // empty' "$_dw_art_tmp")
  [ -n "$_dw_art_current_hash" ] || die "GATE-03 release index has no current $_dw_art_channel hash"
  _dw_art_release=$(jq -c --arg h "$_dw_art_current_hash" --arg c "$_dw_art_channel" --arg a "$_dw_art_release_arch" '
    first(.releases[] | select(.hash == $h and .channel == $c and .dart_sdk_arch == $a)) // empty
  ' "$_dw_art_tmp")
  [ -n "$_dw_art_release" ] || die "GATE-02/03 release index has no $_dw_art_channel release for architecture $_dw_art_release_arch"

  _dw_art_version=$(printf '%s' "$_dw_art_release" | jq -r '.version // empty')
  artifact_validate_version "$_dw_art_version" "$_dw_art_pattern" || die "GATE-03 rejected release-index version: $_dw_art_version"
  _dw_art_archive=$(printf '%s' "$_dw_art_release" | jq -r '.archive // empty')
  artifact_validate_release_archive_path "$_dw_art_archive" || die "GATE-04 rejected unsafe release archive path"
  _dw_art_sha=$(printf '%s' "$_dw_art_release" | jq -r '.sha256 // empty' | tr 'A-F' 'a-f')
  printf '%s\n' "$_dw_art_sha" | grep -Eq '^[0-9a-f]{64}$' || die "GATE-05 release index contains malformed SHA-256"

  jq -nc \
    --arg version "$_dw_art_version" \
    --arg archive "$_dw_art_archive" \
    --arg sha256 "$_dw_art_sha" \
    --arg source_url "$_dw_art_base/$_dw_art_archive" \
    --arg metadata_url "$_dw_art_metadata_url" \
    '{version:$version,archive:$archive,sha256:$sha256,source_url:$source_url,metadata_url:$metadata_url}'
)

plan_verified_binary() {
  _dw_art_env=$1
  _dw_art_target=$2
  _dw_art_version=$(artifact_resolve_version "$_dw_art_env")
  _dw_art_url=$(artifact_render_template "$(printf '%s' "$_dw_art_target" | jq -r '.url_template')" "$_dw_art_version") || die "invalid artifact URL template/version"
  _dw_art_checksum_url=$(artifact_render_template "$(printf '%s' "$_dw_art_target" | jq -r '.checksum_url_template')" "$_dw_art_version") || die "invalid checksum URL template/version"
  _dw_art_destination=$(printf '%s' "$_dw_art_target" | jq -r '.destination')
  _dw_art_path_dir=$(printf '%s' "$_dw_art_target" | jq -r '.path_directory')
  _dw_art_privileged=$(printf '%s' "$_dw_art_target" | jq -r '.privileged')
  printf '  version_source: %s\n' "$(jq -r --arg e "$_dw_art_env" '.artifacts[$e].version.url' "$ARTIFACT_MANIFEST")"
  printf '  resolved_version: %s\n' "$_dw_art_version"
  printf '  url: %s\n' "$_dw_art_url"
  printf '  checksum_url: %s\n' "$_dw_art_checksum_url"
  printf '  integrity: sha256\n'
  printf '  destination: %s\n' "$_dw_art_destination"
  printf '  path_directory: %s\n' "$_dw_art_path_dir"
  printf '  path_mutation: none\n'
  if [ "$_dw_art_privileged" = true ]; then printf '  privilege: root-or-sudo\n'; else printf '  privilege: none\n'; fi
  printf '  conflict_policy: refuse-existing-different-hash-or-symlink\n'
}

plan_verified_archive() {
  _dw_art_env=$1
  _dw_art_target=$2
  _dw_art_release=$(artifact_resolve_release_json "$_dw_art_env" "$_dw_art_target")
  _dw_art_destination=$(artifact_expand_home_path "$(printf '%s' "$_dw_art_target" | jq -r '.destination_template')") || die "invalid archive destination template/HOME"
  _dw_art_path_dir=$(artifact_expand_home_path "$(printf '%s' "$_dw_art_target" | jq -r '.path_directory_template')") || die "invalid archive PATH template/HOME"
  printf '  version_source: %s\n' "$(printf '%s' "$_dw_art_release" | jq -r '.metadata_url')"
  printf '  resolved_version: %s\n' "$(printf '%s' "$_dw_art_release" | jq -r '.version')"
  printf '  url: %s\n' "$(printf '%s' "$_dw_art_release" | jq -r '.source_url')"
  printf '  expected_sha256: %s\n' "$(printf '%s' "$_dw_art_release" | jq -r '.sha256')"
  printf '  integrity: sha256-release-metadata\n'
  printf '  archive_format: %s\n' "$(printf '%s' "$_dw_art_target" | jq -r '.archive_format')"
  printf '  destination: %s\n' "$_dw_art_destination"
  printf '  path_directory: %s\n' "$_dw_art_path_dir"
  printf '  path_mutation: none\n'
  printf '  privilege: none\n'
  printf '  prerequisite: parent directory %s must already exist and not be a symlink\n' "$(dirname "$_dw_art_destination")"
  printf '  prerequisite: PATH must already contain %s\n' "$_dw_art_path_dir"
  printf '  conflict_policy: refuse-unowned-existing-directory-or-symlink\n'
}

plan_verified_artifact() {
  _dw_art_env=$1
  _dw_art_platform=$2
  _dw_art_family=$3
  _dw_art_arch=$4
  _dw_art_target=$(artifact_target_json "$_dw_art_env" "$_dw_art_platform" "$_dw_art_family" "$_dw_art_arch")
  [ -n "$_dw_art_target" ] || return 1
  _dw_art_kind=$(printf '%s' "$_dw_art_target" | jq -r '.kind')
  _dw_art_publisher=$(jq -r --arg e "$_dw_art_env" '.artifacts[$e].publisher' "$ARTIFACT_MANIFEST")
  printf 'artifact:\n'
  printf '  kind: %s\n' "$_dw_art_kind"
  printf '  publisher: %s\n' "$_dw_art_publisher"
  case "$_dw_art_kind" in
    binary) plan_verified_binary "$_dw_art_env" "$_dw_art_target" ;;
    archive) plan_verified_archive "$_dw_art_env" "$_dw_art_target" ;;
    *) die "unsupported artifact target kind: $_dw_art_kind" ;;
  esac
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

install_verified_binary() (
  _dw_art_env=$1
  _dw_art_target=$2
  [ "$(printf '%s' "$_dw_art_target" | jq -r '.integrity')" = sha256 ] || die "unsupported binary artifact integrity policy"
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
      record_artifact_state "$_dw_art_env" "$_dw_art_version" "$_dw_art_url" "$_dw_art_checksum_url" "$_dw_art_destination" "$_dw_art_actual" observed-exact-artifact false
      exit 0
    fi
    die "GATE-08 conflict: $_dw_art_destination already exists with a different SHA-256; explicit upgrade/migration is required"
  fi
  record_artifact_state "$_dw_art_env" "$_dw_art_version" "$_dw_art_url" "$_dw_art_checksum_url" "$_dw_art_destination" "$_dw_art_actual" mutation-intent false
  if [ "$_dw_art_privileged" = true ]; then privileged install -m "$_dw_art_mode" "$_dw_art_payload" "$_dw_art_destination"; else install -m "$_dw_art_mode" "$_dw_art_payload" "$_dw_art_destination"; fi
  _dw_art_installed=$(sha256_file "$_dw_art_destination" | tr 'A-F' 'a-f')
  [ "$_dw_art_installed" = "$_dw_art_actual" ] || die "GATE-12 installed artifact hash differs from verified staged artifact"
  record_artifact_state "$_dw_art_env" "$_dw_art_version" "$_dw_art_url" "$_dw_art_checksum_url" "$_dw_art_destination" "$_dw_art_actual" installed-verified-artifact true
)

artifact_archive_entries_safe() {
  _dw_art_archive=$1
  _dw_art_format=$2
  _dw_art_root=$3
  _dw_art_listing=$4
  case "$_dw_art_format" in
    tar.xz)
      have tar || return 1
      tar -tf "$_dw_art_archive" > "$_dw_art_listing" || return 1
      ;;
    zip)
      have unzip || return 1
      unzip -Z1 "$_dw_art_archive" > "$_dw_art_listing" || return 1
      ;;
    *) return 1 ;;
  esac
  [ -s "$_dw_art_listing" ] || return 1
  awk -v root="$_dw_art_root" '
    {
      path=$0
      if (path ~ /^\// || path ~ /\\/) exit 1
      count=split(path, parts, "/")
      if (parts[1] != root) exit 1
      for (i=1; i<=count; i++) if (parts[i] == "..") exit 1
    }
  ' "$_dw_art_listing"
}

artifact_archive_marker_matches() {
  _dw_art_marker=$1
  _dw_art_env=$2
  _dw_art_version=$3
  _dw_art_url=$4
  _dw_art_sha=$5
  [ -f "$_dw_art_marker" ] && [ ! -L "$_dw_art_marker" ] || return 1
  jq -e --arg e "$_dw_art_env" --arg v "$_dw_art_version" --arg u "$_dw_art_url" --arg s "$_dw_art_sha" '
    .environment == $e and .version == $v and .source_url == $u and .sha256 == $s
  ' "$_dw_art_marker" >/dev/null 2>&1
}

install_verified_archive() (
  _dw_art_env=$1
  _dw_art_target=$2
  [ "$(printf '%s' "$_dw_art_target" | jq -r '.integrity')" = sha256-release-metadata ] || die "unsupported archive artifact integrity policy"
  [ "$(printf '%s' "$_dw_art_target" | jq -r '.privileged')" = false ] || die "archive artifact must be user-scoped"
  _dw_art_destination=$(artifact_expand_home_path "$(printf '%s' "$_dw_art_target" | jq -r '.destination_template')") || die "invalid archive destination template/HOME"
  _dw_art_path_dir=$(artifact_expand_home_path "$(printf '%s' "$_dw_art_target" | jq -r '.path_directory_template')") || die "invalid archive PATH template/HOME"
  _dw_art_parent=$(dirname "$_dw_art_destination")
  _dw_art_format=$(printf '%s' "$_dw_art_target" | jq -r '.archive_format')
  _dw_art_root=$(printf '%s' "$_dw_art_target" | jq -r '.root_directory')

  [ -d "$_dw_art_parent" ] || die "GATE-08 requires archive parent directory to exist first: $_dw_art_parent"
  [ ! -L "$_dw_art_parent" ] || die "GATE-08 refuses symbolic-link archive parent: $_dw_art_parent"
  [ -w "$_dw_art_parent" ] || die "archive parent directory is not writable: $_dw_art_parent"
  artifact_path_declared "$_dw_art_path_dir" || die "GATE-13 requires PATH to already contain $_dw_art_path_dir; devkit-wulf will not modify PATH implicitly"
  artifact_state_ready || die "GATE-10 artifact state path is not safely writable: $STATE_DIR"
  have mktemp || die "mktemp is required for archive installation"

  _dw_art_release=$(artifact_resolve_release_json "$_dw_art_env" "$_dw_art_target")
  _dw_art_version=$(printf '%s' "$_dw_art_release" | jq -r '.version')
  _dw_art_url=$(printf '%s' "$_dw_art_release" | jq -r '.source_url')
  _dw_art_metadata_url=$(printf '%s' "$_dw_art_release" | jq -r '.metadata_url')
  _dw_art_expected=$(printf '%s' "$_dw_art_release" | jq -r '.sha256')

  if [ -e "$_dw_art_destination" ] || [ -L "$_dw_art_destination" ]; then
    [ ! -L "$_dw_art_destination" ] || die "GATE-08 conflict: SDK destination is a symbolic link: $_dw_art_destination"
    [ -d "$_dw_art_destination" ] || die "GATE-08 conflict: SDK destination exists and is not a directory"
    _dw_art_marker="$_dw_art_destination/.devkit-wulf-artifact.json"
    if artifact_archive_marker_matches "$_dw_art_marker" "$_dw_art_env" "$_dw_art_version" "$_dw_art_url" "$_dw_art_expected" && [ -x "$_dw_art_destination/bin/flutter" ]; then
      record_artifact_state "$_dw_art_env" "$_dw_art_version" "$_dw_art_url" "$_dw_art_metadata_url" "$_dw_art_destination" "$_dw_art_expected" observed-exact-artifact false
      exit 0
    fi
    die "GATE-08 conflict: existing SDK directory is not the exact devkit-wulf-managed release"
  fi

  _dw_art_tmpdir=$(mktemp -d "$_dw_art_parent/.devkit-wulf-artifact.XXXXXX") || die "unable to create SDK staging directory"
  trap 'rm -rf "$_dw_art_tmpdir"' EXIT HUP INT TERM
  _dw_art_payload="$_dw_art_tmpdir/archive"
  _dw_art_listing="$_dw_art_tmpdir/archive.list"
  _dw_art_extract="$_dw_art_tmpdir/extracted"
  mkdir "$_dw_art_extract" || die "unable to create extraction staging directory"
  download_https "$_dw_art_url" "$_dw_art_payload"
  _dw_art_actual=$(sha256_file "$_dw_art_payload" | tr 'A-F' 'a-f')
  [ "$_dw_art_actual" != unavailable ] || die "GATE-05 requires a local SHA-256 implementation"
  [ "$_dw_art_actual" = "$_dw_art_expected" ] || die "GATE-05 archive checksum mismatch for $_dw_art_url"
  artifact_archive_entries_safe "$_dw_art_payload" "$_dw_art_format" "$_dw_art_root" "$_dw_art_listing" || die "GATE-05/08 rejected unsafe or unreadable archive contents"

  case "$_dw_art_format" in
    tar.xz) tar -xJf "$_dw_art_payload" -C "$_dw_art_extract" || die "archive extraction failed" ;;
    zip) unzip -q "$_dw_art_payload" -d "$_dw_art_extract" || die "archive extraction failed" ;;
    *) die "unsupported archive format: $_dw_art_format" ;;
  esac
  _dw_art_staged_root="$_dw_art_extract/$_dw_art_root"
  [ -d "$_dw_art_staged_root" ] && [ ! -L "$_dw_art_staged_root" ] || die "GATE-08 extracted SDK root is missing or unsafe"
  [ -x "$_dw_art_staged_root/bin/flutter" ] || die "GATE-12 extracted Flutter executable is missing or not executable"

  jq -nc --arg e "$_dw_art_env" --arg v "$_dw_art_version" --arg u "$_dw_art_url" --arg s "$_dw_art_actual" \
    '{environment:$e,version:$v,source_url:$u,sha256:$s}' > "$_dw_art_staged_root/.devkit-wulf-artifact.json"
  record_artifact_state "$_dw_art_env" "$_dw_art_version" "$_dw_art_url" "$_dw_art_metadata_url" "$_dw_art_destination" "$_dw_art_actual" mutation-intent false
  mv "$_dw_art_staged_root" "$_dw_art_destination" || die "GATE-11 failed to atomically place verified SDK"
  [ -x "$_dw_art_destination/bin/flutter" ] || die "GATE-12 installed Flutter executable is missing"
  record_artifact_state "$_dw_art_env" "$_dw_art_version" "$_dw_art_url" "$_dw_art_metadata_url" "$_dw_art_destination" "$_dw_art_actual" installed-verified-artifact true
)

install_verified_artifact() {
  _dw_art_env=$1
  _dw_art_platform=$2
  _dw_art_family=$3
  _dw_art_arch=$4
  _dw_art_target=$(artifact_target_json "$_dw_art_env" "$_dw_art_platform" "$_dw_art_family" "$_dw_art_arch")
  [ -n "$_dw_art_target" ] || die "no verified artifact mapping for $_dw_art_env on $_dw_art_platform/$_dw_art_arch"
  _dw_art_kind=$(printf '%s' "$_dw_art_target" | jq -r '.kind')
  case "$_dw_art_kind" in
    binary) install_verified_binary "$_dw_art_env" "$_dw_art_target" ;;
    archive) install_verified_archive "$_dw_art_env" "$_dw_art_target" ;;
    *) die "unsupported artifact target kind: $_dw_art_kind" ;;
  esac
}

#!/bin/sh
# Verified JetBrains Toolbox POSIX artifact helper.
# Caller contract: jq, have, log, warn, die, download_https, sha256_file,
# STATE_DIR and JETBRAINS_TOOLBOX_MANIFEST.

jetbrains_toolbox_expand_home() {
  _dw_jb_template=$1
  case "$_dw_jb_template" in '{home}/'*) ;; *) return 1 ;; esac
  [ -n "${HOME:-}" ] || return 1
  case "$HOME" in /*) ;; *) return 1 ;; esac
  case "$HOME" in *'\n'*|*'\r'*) return 1 ;; esac
  _dw_jb_suffix=${_dw_jb_template#\{home\}}
  case "$_dw_jb_suffix" in *'/../'*|'/..'|*'/..') return 1 ;; esac
  printf '%s%s' "$HOME" "$_dw_jb_suffix"
}

jetbrains_toolbox_target_json() {
  _dw_jb_arch=$1
  jq -c --arg a "$_dw_jb_arch" '
    (.targets.linux // null) as $target
    | if $target == null or ($target.architectures[$a] // null) == null then empty
      else (($target | del(.architectures)) + $target.architectures[$a])
      end
  ' "$JETBRAINS_TOOLBOX_MANIFEST"
}

jetbrains_toolbox_validate_version() {
  _dw_jb_version=$1
  _dw_jb_pattern=$(jq -r '.version_pattern' "$JETBRAINS_TOOLBOX_MANIFEST")
  [ -n "$_dw_jb_version" ] || return 1
  case "$_dw_jb_version" in *[!A-Za-z0-9._+-]*) return 1 ;; esac
  printf '%s\n' "$_dw_jb_version" | grep -Eq -- "$_dw_jb_pattern"
}

jetbrains_toolbox_url_allowed() {
  _dw_jb_url=$1
  case "$_dw_jb_url" in https://*) ;; *) return 1 ;; esac
  while IFS= read -r _dw_jb_host; do
    [ -n "$_dw_jb_host" ] || continue
    case "$_dw_jb_url" in "https://$_dw_jb_host/"*) return 0 ;; esac
  done <<EOF
$(jq -r '.allowed_download_hosts[]' "$JETBRAINS_TOOLBOX_MANIFEST")
EOF
  return 1
}

jetbrains_toolbox_state_ready() {
  [ ! -L "$STATE_DIR" ] || return 1
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  [ -d "$STATE_DIR" ] && [ -w "$STATE_DIR" ] || return 1
  _dw_jb_state="$STATE_DIR/jetbrains-toolbox.jsonl"
  [ ! -L "$_dw_jb_state" ] || return 1
  if [ -e "$_dw_jb_state" ]; then
    [ -f "$_dw_jb_state" ] && [ -w "$_dw_jb_state" ] || return 1
  fi
  return 0
}

jetbrains_toolbox_record_state() {
  _dw_jb_action=$1
  _dw_jb_version=$2
  _dw_jb_source=$3
  _dw_jb_checksum=$4
  _dw_jb_destination=$5
  _dw_jb_archive_sha=$6
  _dw_jb_executable_sha=$7
  _dw_jb_created=$8
  jetbrains_toolbox_state_ready || die "GATE-10 JetBrains Toolbox state path is not safely writable: $STATE_DIR"
  _dw_jb_timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  jq -nc \
    --arg timestamp "$_dw_jb_timestamp" \
    --arg action "$_dw_jb_action" \
    --arg version "$_dw_jb_version" \
    --arg source_url "$_dw_jb_source" \
    --arg checksum_url "$_dw_jb_checksum" \
    --arg destination "$_dw_jb_destination" \
    --arg archive_sha256 "$_dw_jb_archive_sha" \
    --arg executable_sha256 "$_dw_jb_executable_sha" \
    --argjson created "$_dw_jb_created" \
    '{timestamp:$timestamp,environment:"jetbrains",publisher:"JetBrains s.r.o.",action:$action,version:$version,source_url:$source_url,checksum_url:$checksum_url,destination:$destination,archive_sha256:$archive_sha256,executable_sha256:$executable_sha256,created:$created,path_mutation:false}' \
    >> "$STATE_DIR/jetbrains-toolbox.jsonl"
}

jetbrains_toolbox_resolve_release() (
  set -eu
  _dw_jb_arch=$1
  _dw_jb_target=$(jetbrains_toolbox_target_json "$_dw_jb_arch")
  [ -n "$_dw_jb_target" ] || die "no JetBrains Toolbox artifact mapping for Linux/$_dw_jb_arch"
  _dw_jb_download_key=$(printf '%s' "$_dw_jb_target" | jq -r '.download_key')
  _dw_jb_api=$(jq -r '.api_url' "$JETBRAINS_TOOLBOX_MANIFEST")
  _dw_jb_code=$(jq -r '.product_code' "$JETBRAINS_TOOLBOX_MANIFEST")
  _dw_jb_type=$(jq -r '.release_type' "$JETBRAINS_TOOLBOX_MANIFEST")
  case "$_dw_jb_api" in https://data.services.jetbrains.com/*) ;; *) die "GATE-04 JetBrains release API is not the pinned official service" ;; esac
  have mktemp || die "mktemp is required for JetBrains Toolbox release resolution"
  _dw_jb_tmp=$(mktemp "${TMPDIR:-/tmp}/devkit-wulf-jetbrains-api.XXXXXX") || die "unable to create JetBrains release-index staging file"
  trap 'rm -f "$_dw_jb_tmp"' EXIT HUP INT TERM
  download_https "$_dw_jb_api" "$_dw_jb_tmp"
  jq -e . "$_dw_jb_tmp" >/dev/null 2>&1 || die "GATE-03 JetBrains release response is not valid JSON"
  _dw_jb_release=$(jq -c --arg code "$_dw_jb_code" --arg type "$_dw_jb_type" 'first(.[$code][]? | select(.type == $type)) // empty' "$_dw_jb_tmp")
  [ -n "$_dw_jb_release" ] || die "GATE-03 JetBrains release service returned no matching release"
  _dw_jb_version=$(printf '%s' "$_dw_jb_release" | jq -r '.version // empty')
  jetbrains_toolbox_validate_version "$_dw_jb_version" || die "GATE-03 rejected JetBrains Toolbox version: $_dw_jb_version"
  _dw_jb_source=$(printf '%s' "$_dw_jb_release" | jq -r --arg key "$_dw_jb_download_key" '.downloads[$key].link // empty')
  _dw_jb_checksum=$(printf '%s' "$_dw_jb_release" | jq -r --arg key "$_dw_jb_download_key" '.downloads[$key].checksumLink // empty')
  jetbrains_toolbox_url_allowed "$_dw_jb_source" || die "GATE-04 JetBrains archive URL is outside the allowed official download hosts"
  jetbrains_toolbox_url_allowed "$_dw_jb_checksum" || die "GATE-04 JetBrains checksum URL is outside the allowed official download hosts"
  case "$_dw_jb_source" in *.tar.gz) ;; *) die "GATE-03 JetBrains Linux release is not a tar.gz archive" ;; esac
  _dw_jb_root_template=$(printf '%s' "$_dw_jb_target" | jq -r '.root_directory_template')
  _dw_jb_root=$(printf '%s' "$_dw_jb_root_template" | sed "s/{version}/$_dw_jb_version/g")
  printf '%s\n' "$_dw_jb_root" | grep -Eq '^jetbrains-toolbox-[A-Za-z0-9._+-]+$' || die "GATE-03 unsafe JetBrains archive root"
  jq -nc \
    --arg version "$_dw_jb_version" \
    --arg source_url "$_dw_jb_source" \
    --arg checksum_url "$_dw_jb_checksum" \
    --arg root_directory "$_dw_jb_root" \
    --arg download_key "$_dw_jb_download_key" \
    --arg api_url "$_dw_jb_api" \
    '{version:$version,source_url:$source_url,checksum_url:$checksum_url,root_directory:$root_directory,download_key:$download_key,api_url:$api_url}'
)

jetbrains_toolbox_archive_safe() {
  _dw_jb_archive=$1
  _dw_jb_root=$2
  _dw_jb_exec=$3
  _dw_jb_listing=$4
  have tar || return 1
  tar -tzf "$_dw_jb_archive" > "$_dw_jb_listing" || return 1
  [ -s "$_dw_jb_listing" ] || return 1
  awk -v root="$_dw_jb_root" '
    {
      path=$0
      if (path ~ /^\// || path ~ /\\/) exit 1
      count=split(path, parts, "/")
      if (parts[1] != root) exit 1
      for (i=1; i<=count; i++) if (parts[i] == "..") exit 1
    }
  ' "$_dw_jb_listing" || return 1
  grep -Fxq "$_dw_jb_root/$_dw_jb_exec" "$_dw_jb_listing"
}

jetbrains_toolbox_marker_integrity() {
  _dw_jb_marker=$1
  _dw_jb_destination=$2
  [ -f "$_dw_jb_marker" ] && [ ! -L "$_dw_jb_marker" ] || return 1
  [ -f "$_dw_jb_destination" ] && [ ! -L "$_dw_jb_destination" ] && [ -x "$_dw_jb_destination" ] || return 1
  _dw_jb_current_sha=$(sha256_file "$_dw_jb_destination")
  [ "$_dw_jb_current_sha" != unavailable ] || return 1
  _dw_jb_version=$(jq -r '.version // empty' "$_dw_jb_marker" 2>/dev/null) || return 1
  jetbrains_toolbox_validate_version "$_dw_jb_version" || return 1
  jq -e --arg executable_sha "$_dw_jb_current_sha" '
    .environment == "jetbrains" and
    .publisher == "JetBrains s.r.o." and
    (.source_url | type == "string") and
    (.archive_sha256 | test("^[0-9a-fA-F]{64}$")) and
    .executable_sha256 == $executable_sha
  ' "$_dw_jb_marker" >/dev/null 2>&1
}

jetbrains_toolbox_marker_matches() {
  _dw_jb_marker=$1
  _dw_jb_destination=$2
  _dw_jb_version=$3
  _dw_jb_source=$4
  _dw_jb_archive_sha=$5
  jetbrains_toolbox_marker_integrity "$_dw_jb_marker" "$_dw_jb_destination" || return 1
  jq -e \
    --arg version "$_dw_jb_version" \
    --arg source "$_dw_jb_source" \
    --arg archive_sha "$_dw_jb_archive_sha" '
      .version == $version and .source_url == $source and .archive_sha256 == $archive_sha
    ' "$_dw_jb_marker" >/dev/null 2>&1
}

verify_jetbrains_toolbox() {
  _dw_jb_arch=$1
  _dw_jb_target=$(jetbrains_toolbox_target_json "$_dw_jb_arch")
  [ -n "$_dw_jb_target" ] || return 1
  _dw_jb_destination=$(jetbrains_toolbox_expand_home "$(printf '%s' "$_dw_jb_target" | jq -r '.destination_template')") || return 1
  _dw_jb_marker=$(jetbrains_toolbox_expand_home "$(printf '%s' "$_dw_jb_target" | jq -r '.marker_template')") || return 1
  jetbrains_toolbox_marker_integrity "$_dw_jb_marker" "$_dw_jb_destination" || return 1
  _dw_jb_output=$("$_dw_jb_destination" --version 2>&1) || return 1
  [ -n "$_dw_jb_output" ]
}

plan_jetbrains_toolbox() {
  _dw_jb_arch=$1
  _dw_jb_target=$(jetbrains_toolbox_target_json "$_dw_jb_arch")
  [ -n "$_dw_jb_target" ] || return 1
  _dw_jb_release=$(jetbrains_toolbox_resolve_release "$_dw_jb_arch")
  _dw_jb_destination=$(jetbrains_toolbox_expand_home "$(printf '%s' "$_dw_jb_target" | jq -r '.destination_template')") || die "invalid JetBrains Toolbox destination/HOME"
  _dw_jb_path=$(jetbrains_toolbox_expand_home "$(printf '%s' "$_dw_jb_target" | jq -r '.path_directory_template')") || die "invalid JetBrains Toolbox PATH directory/HOME"
  printf 'jetbrains_toolbox:\n'
  printf '  publisher: JetBrains s.r.o.\n'
  printf '  release_api: %s\n' "$(printf '%s' "$_dw_jb_release" | jq -r '.api_url')"
  printf '  download_key: %s\n' "$(printf '%s' "$_dw_jb_release" | jq -r '.download_key')"
  printf '  resolved_version: %s\n' "$(printf '%s' "$_dw_jb_release" | jq -r '.version')"
  printf '  url: %s\n' "$(printf '%s' "$_dw_jb_release" | jq -r '.source_url')"
  printf '  checksum_url: %s\n' "$(printf '%s' "$_dw_jb_release" | jq -r '.checksum_url')"
  printf '  integrity: sha256-link\n'
  printf '  destination: %s\n' "$_dw_jb_destination"
  printf '  path_directory: %s\n' "$_dw_jb_path"
  printf '  path_mutation: none\n'
  printf '  privilege: none\n'
  printf '  conflict_policy: refuse-unowned-existing-binary-or-marker\n'
}

jetbrains_toolbox_cleanup_install() {
  [ -n "${_dw_jb_marker_tmp:-}" ] && rm -f "$_dw_jb_marker_tmp"
  if [ -n "${_dw_jb_tmpdir:-}" ]; then
    [ -n "${_dw_jb_staged_exec:-}" ] && rm -f "$_dw_jb_staged_exec"
    [ -n "${_dw_jb_root:-}" ] && [ -n "${_dw_jb_extract:-}" ] && rmdir "$_dw_jb_extract/$_dw_jb_root" 2>/dev/null || true
    [ -n "${_dw_jb_extract:-}" ] && rmdir "$_dw_jb_extract" 2>/dev/null || true
    rm -f "$_dw_jb_tmpdir/toolbox.tar.gz" "$_dw_jb_tmpdir/toolbox.sha256" "$_dw_jb_tmpdir/archive.list"
    rmdir "$_dw_jb_tmpdir" 2>/dev/null || true
  fi
}

install_jetbrains_toolbox() (
  set -eu
  _dw_jb_arch=$1
  _dw_jb_marker_tmp=
  _dw_jb_staged_exec=
  _dw_jb_tmpdir=
  _dw_jb_extract=
  _dw_jb_root=
  _dw_jb_target=$(jetbrains_toolbox_target_json "$_dw_jb_arch")
  [ -n "$_dw_jb_target" ] || die "no JetBrains Toolbox artifact mapping for Linux/$_dw_jb_arch"
  _dw_jb_destination=$(jetbrains_toolbox_expand_home "$(printf '%s' "$_dw_jb_target" | jq -r '.destination_template')") || die "invalid JetBrains Toolbox destination/HOME"
  _dw_jb_path=$(jetbrains_toolbox_expand_home "$(printf '%s' "$_dw_jb_target" | jq -r '.path_directory_template')") || die "invalid JetBrains Toolbox PATH directory/HOME"
  _dw_jb_marker=$(jetbrains_toolbox_expand_home "$(printf '%s' "$_dw_jb_target" | jq -r '.marker_template')") || die "invalid JetBrains Toolbox marker/HOME"
  _dw_jb_exec_rel=$(printf '%s' "$_dw_jb_target" | jq -r '.executable_relative_path')
  [ -d "$_dw_jb_path" ] && [ ! -L "$_dw_jb_path" ] && [ -w "$_dw_jb_path" ] || die "GATE-08 JetBrains Toolbox install directory must already exist, be writable, and not be a symlink: $_dw_jb_path"
  case ":${PATH:-}:" in *":$_dw_jb_path:"*) ;; *) die "GATE-13 PATH must already contain $_dw_jb_path; devkit-wulf will not modify PATH implicitly" ;; esac
  jetbrains_toolbox_state_ready || die "GATE-10 JetBrains Toolbox state path is not safely writable: $STATE_DIR"
  have mktemp || die "mktemp is required for JetBrains Toolbox installation"
  have install || die "POSIX install utility is required for JetBrains Toolbox installation"

  _dw_jb_release=$(jetbrains_toolbox_resolve_release "$_dw_jb_arch")
  _dw_jb_version=$(printf '%s' "$_dw_jb_release" | jq -r '.version')
  _dw_jb_source=$(printf '%s' "$_dw_jb_release" | jq -r '.source_url')
  _dw_jb_checksum=$(printf '%s' "$_dw_jb_release" | jq -r '.checksum_url')
  _dw_jb_root=$(printf '%s' "$_dw_jb_release" | jq -r '.root_directory')

  _dw_jb_tmpdir=$(mktemp -d "$_dw_jb_path/.devkit-wulf-jetbrains.XXXXXX") || die "unable to create JetBrains Toolbox staging directory"
  trap 'jetbrains_toolbox_cleanup_install' EXIT HUP INT TERM
  _dw_jb_archive="$_dw_jb_tmpdir/toolbox.tar.gz"
  _dw_jb_checksum_file="$_dw_jb_tmpdir/toolbox.sha256"
  _dw_jb_listing="$_dw_jb_tmpdir/archive.list"
  _dw_jb_extract="$_dw_jb_tmpdir/extract"
  mkdir "$_dw_jb_extract" || die "unable to create JetBrains Toolbox extraction directory"

  download_https "$_dw_jb_checksum" "$_dw_jb_checksum_file"
  _dw_jb_expected=$(awk 'NR==1 {print $1}' "$_dw_jb_checksum_file" | tr 'A-F' 'a-f')
  printf '%s\n' "$_dw_jb_expected" | grep -Eq '^[0-9a-f]{64}$' || die "GATE-05 JetBrains checksum endpoint returned malformed SHA-256"
  download_https "$_dw_jb_source" "$_dw_jb_archive"
  _dw_jb_actual=$(sha256_file "$_dw_jb_archive" | tr 'A-F' 'a-f')
  [ "$_dw_jb_actual" != unavailable ] || die "GATE-05 requires a local SHA-256 implementation"
  [ "$_dw_jb_actual" = "$_dw_jb_expected" ] || die "GATE-05 JetBrains Toolbox archive checksum mismatch"
  jetbrains_toolbox_archive_safe "$_dw_jb_archive" "$_dw_jb_root" "$_dw_jb_exec_rel" "$_dw_jb_listing" || die "GATE-05/08 rejected unsafe JetBrains Toolbox archive contents"

  if [ -e "$_dw_jb_destination" ] || [ -L "$_dw_jb_destination" ] || [ -e "$_dw_jb_marker" ] || [ -L "$_dw_jb_marker" ]; then
    [ ! -L "$_dw_jb_destination" ] || die "GATE-08 JetBrains Toolbox destination is a symlink"
    [ ! -L "$_dw_jb_marker" ] || die "GATE-08 JetBrains Toolbox marker is a symlink"
    if jetbrains_toolbox_marker_matches "$_dw_jb_marker" "$_dw_jb_destination" "$_dw_jb_version" "$_dw_jb_source" "$_dw_jb_actual"; then
      _dw_jb_exec_sha=$(sha256_file "$_dw_jb_destination")
      jetbrains_toolbox_record_state observed-exact-artifact "$_dw_jb_version" "$_dw_jb_source" "$_dw_jb_checksum" "$_dw_jb_destination" "$_dw_jb_actual" "$_dw_jb_exec_sha" false
      jetbrains_toolbox_cleanup_install
      _dw_jb_tmpdir=
      trap - EXIT HUP INT TERM
      exit 0
    fi
    die "GATE-08 existing JetBrains Toolbox binary/marker is not the exact devkit-wulf-managed release"
  fi

  tar -xzf "$_dw_jb_archive" -C "$_dw_jb_extract" "$_dw_jb_root/$_dw_jb_exec_rel" || die "JetBrains Toolbox executable extraction failed"
  _dw_jb_staged_exec="$_dw_jb_extract/$_dw_jb_root/$_dw_jb_exec_rel"
  [ -f "$_dw_jb_staged_exec" ] && [ ! -L "$_dw_jb_staged_exec" ] && [ -x "$_dw_jb_staged_exec" ] || die "GATE-12 extracted JetBrains Toolbox executable is missing, linked, or not executable"
  _dw_jb_exec_sha=$(sha256_file "$_dw_jb_staged_exec")
  [ "$_dw_jb_exec_sha" != unavailable ] || die "GATE-05 requires SHA-256 for extracted executable ownership"

  jetbrains_toolbox_record_state mutation-intent "$_dw_jb_version" "$_dw_jb_source" "$_dw_jb_checksum" "$_dw_jb_destination" "$_dw_jb_actual" "$_dw_jb_exec_sha" false
  install -m 0755 "$_dw_jb_staged_exec" "$_dw_jb_destination"
  _dw_jb_installed_sha=$(sha256_file "$_dw_jb_destination")
  [ "$_dw_jb_installed_sha" = "$_dw_jb_exec_sha" ] || die "GATE-12 installed JetBrains Toolbox executable differs from staged executable"

  _dw_jb_marker_tmp=$(mktemp "$_dw_jb_path/.devkit-wulf-jetbrains-marker.XXXXXX") || die "unable to create JetBrains Toolbox marker staging file"
  jq -nc \
    --arg version "$_dw_jb_version" \
    --arg source_url "$_dw_jb_source" \
    --arg archive_sha256 "$_dw_jb_actual" \
    --arg executable_sha256 "$_dw_jb_exec_sha" \
    '{environment:"jetbrains",publisher:"JetBrains s.r.o.",version:$version,source_url:$source_url,archive_sha256:$archive_sha256,executable_sha256:$executable_sha256}' \
    > "$_dw_jb_marker_tmp"
  mv "$_dw_jb_marker_tmp" "$_dw_jb_marker" || die "failed to place JetBrains Toolbox ownership marker"
  _dw_jb_marker_tmp=
  verify_jetbrains_toolbox "$_dw_jb_arch" || die "GATE-12 installed JetBrains Toolbox managed verification failed"
  jetbrains_toolbox_record_state installed-verified-artifact "$_dw_jb_version" "$_dw_jb_source" "$_dw_jb_checksum" "$_dw_jb_destination" "$_dw_jb_actual" "$_dw_jb_exec_sha" true
  jetbrains_toolbox_cleanup_install
  _dw_jb_tmpdir=
  trap - EXIT HUP INT TERM
)

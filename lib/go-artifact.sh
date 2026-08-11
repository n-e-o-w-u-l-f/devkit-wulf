#!/bin/sh
# Verified Go toolchain artifact helper.
# Caller contract: jq, have, die, download_https, sha256_file,
# STATE_DIR and GO_ARTIFACT_MANIFEST.

go_artifact_expand_home() {
  _dw_go_template=$1
  case "$_dw_go_template" in '{home}/'*) ;; *) return 1 ;; esac
  [ -n "${HOME:-}" ] || return 1
  case "$HOME" in /*) ;; *) return 1 ;; esac
  _dw_go_suffix=${_dw_go_template#\{home\}}
  case "$_dw_go_suffix" in *'/../'*|'/..'|*'/..') return 1 ;; esac
  printf '%s%s' "$HOME" "$_dw_go_suffix"
}

go_artifact_destination() { go_artifact_expand_home "$(jq -r '.install.destination_template' "$GO_ARTIFACT_MANIFEST")"; }
go_artifact_path_dir() { go_artifact_expand_home "$(jq -r '.install.path_directory_template' "$GO_ARTIFACT_MANIFEST")"; }
go_artifact_marker() { go_artifact_expand_home "$(jq -r '.install.marker_template' "$GO_ARTIFACT_MANIFEST")"; }

go_artifact_target_json() {
  _dw_go_platform=$1
  _dw_go_arch=$2
  jq -c --arg p "$_dw_go_platform" --arg a "$_dw_go_arch" '
    .targets[$p] as $target
    | if $target == null or (($target.architectures // []) | index($a)) == null then empty
      else {go_os:$target.go_os,archive_format:$target.archive_format,arch:$a}
      end
  ' "$GO_ARTIFACT_MANIFEST"
}

go_artifact_state_ready() {
  [ ! -L "$STATE_DIR" ] || return 1
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  [ -d "$STATE_DIR" ] && [ -w "$STATE_DIR" ] || return 1
  _dw_go_state="$STATE_DIR/go-artifact.jsonl"
  [ ! -L "$_dw_go_state" ] || return 1
  if [ -e "$_dw_go_state" ]; then [ -f "$_dw_go_state" ] && [ -w "$_dw_go_state" ] || return 1; fi
}

go_artifact_record_state() {
  _dw_go_action=$1
  _dw_go_platform=$2
  _dw_go_arch=$3
  _dw_go_version=$4
  _dw_go_source=$5
  _dw_go_sha=$6
  _dw_go_destination=$7
  _dw_go_created=$8
  go_artifact_state_ready || die "GATE-10 Go state path is not safely writable: $STATE_DIR"
  _dw_go_timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  jq -nc --arg timestamp "$_dw_go_timestamp" --arg action "$_dw_go_action" --arg platform "$_dw_go_platform" --arg architecture "$_dw_go_arch" \
    --arg version "$_dw_go_version" --arg source_url "$_dw_go_source" --arg archive_sha256 "$_dw_go_sha" --arg destination "$_dw_go_destination" --argjson created "$_dw_go_created" \
    '{timestamp:$timestamp,environment:"go",publisher:"The Go Authors",action:$action,platform:$platform,architecture:$architecture,version:$version,source_url:$source_url,archive_sha256:$archive_sha256,destination:$destination,created:$created,path_mutation:false,privileged:false}' \
    >> "$STATE_DIR/go-artifact.jsonl"
}

go_artifact_assert_path_declared() {
  _dw_go_path=$1
  case ":${PATH:-}:" in *":$_dw_go_path:"*) return 0 ;; esac
  die "GATE-13 PATH must already contain $_dw_go_path; devkit-wulf will not modify PATH implicitly"
}

go_artifact_resolve_release() {
  _dw_go_platform=$1
  _dw_go_arch=$2
  _dw_go_target=$(go_artifact_target_json "$_dw_go_platform" "$_dw_go_arch")
  [ -n "$_dw_go_target" ] || return 1
  _dw_go_os=$(printf '%s' "$_dw_go_target" | jq -r '.go_os')
  _dw_go_index=$(jq -r '.release_index_url' "$GO_ARTIFACT_MANIFEST")
  _dw_go_base=$(jq -r '.download_base' "$GO_ARTIFACT_MANIFEST")
  [ "$_dw_go_index" = 'https://go.dev/dl/?mode=json' ] || return 1
  [ "$_dw_go_base" = 'https://go.dev/dl' ] || return 1
  _dw_go_tmp=$(mktemp "${TMPDIR:-/tmp}/devkit-wulf-go-index.XXXXXX") || return 1
  if download_https "$_dw_go_index" "$_dw_go_tmp"; then :; else rm -f "$_dw_go_tmp"; return 1; fi
  _dw_go_release=$(jq -c '[.[] | select(.stable == true)][0] // empty' "$_dw_go_tmp")
  rm -f "$_dw_go_tmp"
  [ -n "$_dw_go_release" ] && [ "$_dw_go_release" != null ] || return 1
  _dw_go_version=$(printf '%s' "$_dw_go_release" | jq -r '.version')
  _dw_go_pattern=$(jq -r '.version_pattern' "$GO_ARTIFACT_MANIFEST")
  printf '%s\n' "$_dw_go_version" | grep -Eq "$_dw_go_pattern" || return 1
  case "$_dw_go_version" in *'/'*|*'\\'*|*'..'*) return 1 ;; esac
  _dw_go_file=$(printf '%s' "$_dw_go_release" | jq -c --arg os "$_dw_go_os" --arg arch "$_dw_go_arch" '[.files[] | select(.os == $os and .arch == $arch and .kind == "archive")][0] // empty')
  [ -n "$_dw_go_file" ] && [ "$_dw_go_file" != null ] || return 1
  _dw_go_filename=$(printf '%s' "$_dw_go_file" | jq -r '.filename')
  _dw_go_sha=$(printf '%s' "$_dw_go_file" | jq -r '.sha256' | tr 'A-F' 'a-f')
  case "$_dw_go_filename" in *'/'*|*'\\'*|*'..'*) return 1 ;; esac
  printf '%s\n' "$_dw_go_filename" | grep -Eq '^go[0-9]+[.][0-9]+([.][0-9]+)?[.](linux|darwin)-(amd64|arm64|riscv64|ppc64le|s390x)[.]tar[.]gz$' || return 1
  printf '%s\n' "$_dw_go_sha" | grep -Eq '^[0-9a-f]{64}$' || return 1
  _dw_go_source="$_dw_go_base/$_dw_go_filename"
  jq -nc --arg version "$_dw_go_version" --arg filename "$_dw_go_filename" --arg sha256 "$_dw_go_sha" --arg source_url "$_dw_go_source" --arg go_os "$_dw_go_os" --arg arch "$_dw_go_arch" '{version:$version,filename:$filename,sha256:$sha256,source_url:$source_url,go_os:$go_os,arch:$arch}'
}

go_artifact_tar_safe() {
  _dw_go_archive=$1
  _dw_go_names=$(mktemp "${TMPDIR:-/tmp}/devkit-wulf-go-names.XXXXXX") || return 1
  _dw_go_verbose=$(mktemp "${TMPDIR:-/tmp}/devkit-wulf-go-types.XXXXXX") || { rm -f "$_dw_go_names"; return 1; }
  if tar -tzf "$_dw_go_archive" > "$_dw_go_names" && tar -tvzf "$_dw_go_archive" > "$_dw_go_verbose"; then :; else rm -f "$_dw_go_names" "$_dw_go_verbose"; return 1; fi
  _dw_go_ok=true
  while IFS= read -r _dw_go_name; do
    [ -n "$_dw_go_name" ] || { _dw_go_ok=false; break; }
    case "$_dw_go_name" in go|go/|go/*) ;; *) _dw_go_ok=false; break ;; esac
    case "$_dw_go_name" in /*|*'\\'*|*'/../'*|../*|*'/..') _dw_go_ok=false; break ;; esac
  done < "$_dw_go_names"
  if [ "$_dw_go_ok" = true ]; then
    awk '{t=substr($0,1,1); if (t != "-" && t != "d") exit 1}' "$_dw_go_verbose" || _dw_go_ok=false
  fi
  rm -f "$_dw_go_names" "$_dw_go_verbose"
  [ "$_dw_go_ok" = true ]
}

go_artifact_binary_hash() {
  _dw_go_destination=$1
  _dw_go_name=$2
  _dw_go_file="$_dw_go_destination/bin/$_dw_go_name"
  [ -f "$_dw_go_file" ] && [ ! -L "$_dw_go_file" ] && [ -x "$_dw_go_file" ] || return 1
  _dw_go_sha=$(sha256_file "$_dw_go_file")
  [ "$_dw_go_sha" != unavailable ] || return 1
  printf '%s' "$_dw_go_sha"
}

verify_go_artifact() {
  _dw_go_platform=$1
  _dw_go_arch=$2
  [ -n "$(go_artifact_target_json "$_dw_go_platform" "$_dw_go_arch" || true)" ] || return 1
  _dw_go_destination=$(go_artifact_destination) || return 1
  _dw_go_marker=$(go_artifact_marker) || return 1
  [ -d "$_dw_go_destination" ] && [ ! -L "$_dw_go_destination" ] || return 1
  [ -f "$_dw_go_marker" ] && [ ! -L "$_dw_go_marker" ] || return 1
  jq -e --arg p "$_dw_go_platform" --arg a "$_dw_go_arch" '
    .environment == "go" and .publisher == "The Go Authors" and .platform == $p and .architecture == $a and
    (.version | test("^go[0-9]+[.][0-9]+([.][0-9]+)?$")) and
    (.source_url | test("^https://go[.]dev/dl/go")) and (.archive_sha256 | test("^[0-9a-fA-F]{64}$"))
  ' "$_dw_go_marker" >/dev/null 2>&1 || return 1
  for _dw_go_name in go gofmt; do
    _dw_go_sha=$(go_artifact_binary_hash "$_dw_go_destination" "$_dw_go_name") || return 1
    jq -e --arg n "$_dw_go_name" --arg h "$_dw_go_sha" '.critical_files[$n] == $h' "$_dw_go_marker" >/dev/null 2>&1 || return 1
  done
  "$_dw_go_destination/bin/go" version >/dev/null 2>&1 || return 1
  "$_dw_go_destination/bin/go" env GOHOSTOS GOHOSTARCH >/dev/null 2>&1 || return 1
}

plan_go_artifact() {
  _dw_go_platform=$1
  _dw_go_arch=$2
  _dw_go_release=$(go_artifact_resolve_release "$_dw_go_platform" "$_dw_go_arch") || return 1
  _dw_go_destination=$(go_artifact_destination) || return 1
  _dw_go_path=$(go_artifact_path_dir) || return 1
  printf 'go_artifact:\n'
  printf '  publisher: The Go Authors\n'
  printf '  version: %s\n' "$(printf '%s' "$_dw_go_release" | jq -r '.version')"
  printf '  url: %s\n' "$(printf '%s' "$_dw_go_release" | jq -r '.source_url')"
  printf '  sha256: %s\n' "$(printf '%s' "$_dw_go_release" | jq -r '.sha256')"
  printf '  destination: %s\n' "$_dw_go_destination"
  printf '  path_directory: %s\n' "$_dw_go_path"
  printf '  integrity: sha256-release-index\n'
  printf '  path_mutation: none\n'
  printf '  privilege: none\n'
  printf '  mutates_host: false\n'
}

go_artifact_cleanup_stage() {
  _dw_go_stage=$1
  _dw_go_parent=$2
  [ -n "$_dw_go_stage" ] && [ -e "$_dw_go_stage" ] || return 0
  [ ! -L "$_dw_go_stage" ] || return 1
  case "$_dw_go_stage" in "$_dw_go_parent"/.devkit-wulf-go.*) ;; *) return 1 ;; esac
  rm -rf "$_dw_go_stage"
}

install_go_artifact() (
  set -eu
  _dw_go_platform=$1
  _dw_go_arch=$2
  [ -n "$(go_artifact_target_json "$_dw_go_platform" "$_dw_go_arch" || true)" ] || die "no verified Go artifact for $_dw_go_platform/$_dw_go_arch"
  _dw_go_destination=$(go_artifact_destination) || die "invalid Go destination"
  _dw_go_path=$(go_artifact_path_dir) || die "invalid Go PATH directory"
  _dw_go_marker=$(go_artifact_marker) || die "invalid Go marker"
  _dw_go_parent=$(dirname "$_dw_go_destination")
  _dw_go_local_share=$(dirname "$_dw_go_parent")
  [ -d "$_dw_go_local_share" ] && [ ! -L "$_dw_go_local_share" ] && [ -w "$_dw_go_local_share" ] || die "GATE-08 Go parent must exist, be writable and not be a symlink: $_dw_go_local_share"
  if [ ! -e "$_dw_go_parent" ]; then mkdir "$_dw_go_parent" || die "unable to create devkit-wulf user data root"; fi
  [ -d "$_dw_go_parent" ] && [ ! -L "$_dw_go_parent" ] && [ -w "$_dw_go_parent" ] || die "GATE-08 Go data root is unsafe: $_dw_go_parent"
  go_artifact_assert_path_declared "$_dw_go_path"
  go_artifact_state_ready || die "GATE-10 Go state path is not safely writable: $STATE_DIR"

  if [ -e "$_dw_go_destination" ] || [ -L "$_dw_go_destination" ]; then
    [ ! -L "$_dw_go_destination" ] || die "GATE-08 Go destination is a symlink"
    if verify_go_artifact "$_dw_go_platform" "$_dw_go_arch"; then
      _dw_go_version=$(jq -r '.version' "$_dw_go_marker")
      _dw_go_source=$(jq -r '.source_url' "$_dw_go_marker")
      _dw_go_sha=$(jq -r '.archive_sha256' "$_dw_go_marker")
      go_artifact_record_state observed-managed "$_dw_go_platform" "$_dw_go_arch" "$_dw_go_version" "$_dw_go_source" "$_dw_go_sha" "$_dw_go_destination" false
      exit 0
    fi
    die "GATE-08 existing Go destination is not an exact devkit-wulf-managed toolchain"
  fi

  _dw_go_release=$(go_artifact_resolve_release "$_dw_go_platform" "$_dw_go_arch") || die "unable to resolve current stable Go artifact"
  _dw_go_version=$(printf '%s' "$_dw_go_release" | jq -r '.version')
  _dw_go_source=$(printf '%s' "$_dw_go_release" | jq -r '.source_url')
  _dw_go_expected=$(printf '%s' "$_dw_go_release" | jq -r '.sha256')
  _dw_go_stage=$(mktemp -d "$_dw_go_parent/.devkit-wulf-go.XXXXXX") || die "unable to create Go staging directory"
  trap 'go_artifact_cleanup_stage "$_dw_go_stage" "$_dw_go_parent" || true' EXIT HUP INT TERM
  _dw_go_archive="$_dw_go_stage/go.tar.gz"
  download_https "$_dw_go_source" "$_dw_go_archive"
  _dw_go_actual=$(sha256_file "$_dw_go_archive" | tr 'A-F' 'a-f')
  [ "$_dw_go_actual" != unavailable ] || die "GATE-05 requires a local SHA-256 implementation"
  [ "$_dw_go_actual" = "$_dw_go_expected" ] || die "GATE-05 Go archive SHA-256 mismatch"
  go_artifact_tar_safe "$_dw_go_archive" || die "GATE-05/08 rejected unsafe Go tar archive"
  tar -xzf "$_dw_go_archive" -C "$_dw_go_stage" || die "unable to extract verified Go archive"
  [ -d "$_dw_go_stage/go" ] && [ ! -L "$_dw_go_stage/go" ] || die "GATE-12 extracted Go root is missing or unsafe"
  if find "$_dw_go_stage/go" -type l -print -quit | grep -q .; then die "GATE-12 extracted Go tree contains a symlink"; fi
  _dw_go_go_sha=$(go_artifact_binary_hash "$_dw_go_stage/go" go) || die "GATE-12 staged go binary missing"
  _dw_go_gofmt_sha=$(go_artifact_binary_hash "$_dw_go_stage/go" gofmt) || die "GATE-12 staged gofmt binary missing"
  "$_dw_go_stage/go/bin/go" version >/dev/null 2>&1 || die "GATE-12 staged go version failed"
  "$_dw_go_stage/go/bin/go" env GOHOSTOS GOHOSTARCH >/dev/null 2>&1 || die "GATE-12 staged go env failed"
  jq -nc --arg p "$_dw_go_platform" --arg a "$_dw_go_arch" --arg v "$_dw_go_version" --arg s "$_dw_go_source" --arg h "$_dw_go_actual" --arg go "$_dw_go_go_sha" --arg gofmt "$_dw_go_gofmt_sha" \
    '{environment:"go",publisher:"The Go Authors",platform:$p,architecture:$a,version:$v,source_url:$s,archive_sha256:$h,critical_files:{go:$go,gofmt:$gofmt}}' > "$_dw_go_stage/go/.devkit-wulf-go.json"
  go_artifact_record_state mutation-intent "$_dw_go_platform" "$_dw_go_arch" "$_dw_go_version" "$_dw_go_source" "$_dw_go_actual" "$_dw_go_destination" false
  mv "$_dw_go_stage/go" "$_dw_go_destination" || die "unable to place verified Go toolchain"
  verify_go_artifact "$_dw_go_platform" "$_dw_go_arch" || die "GATE-12 managed Go verification failed after placement"
  go_artifact_record_state installed-verified "$_dw_go_platform" "$_dw_go_arch" "$_dw_go_version" "$_dw_go_source" "$_dw_go_actual" "$_dw_go_destination" true
  go_artifact_cleanup_stage "$_dw_go_stage" "$_dw_go_parent"
  trap - EXIT HUP INT TERM
)

#!/bin/sh
# Verified rustup-init artifact helper.
# Caller contract: jq, have, die, download_https, sha256_file,
# STATE_DIR and RUSTUP_ARTIFACT_MANIFEST.

rustup_artifact_expand_home() {
  _dw_ru_template=$1
  case "$_dw_ru_template" in '{home}/'*) ;; *) return 1 ;; esac
  [ -n "${HOME:-}" ] || return 1
  case "$HOME" in /*) ;; *) return 1 ;; esac
  _dw_ru_suffix=${_dw_ru_template#\{home\}}
  case "$_dw_ru_suffix" in *'/../'*|'/..'|*'/..') return 1 ;; esac
  printf '%s%s' "$HOME" "$_dw_ru_suffix"
}

rustup_artifact_cargo_home() { rustup_artifact_expand_home "$(jq -r '.install.cargo_home_template' "$RUSTUP_ARTIFACT_MANIFEST")"; }
rustup_artifact_rustup_home() { rustup_artifact_expand_home "$(jq -r '.install.rustup_home_template' "$RUSTUP_ARTIFACT_MANIFEST")"; }
rustup_artifact_path_dir() { rustup_artifact_expand_home "$(jq -r '.install.path_directory_template' "$RUSTUP_ARTIFACT_MANIFEST")"; }
rustup_artifact_marker() { rustup_artifact_expand_home "$(jq -r '.install.marker_template' "$RUSTUP_ARTIFACT_MANIFEST")"; }

rustup_artifact_target_json() {
  _dw_ru_platform=$1
  _dw_ru_arch=$2
  jq -c --arg p "$_dw_ru_platform" --arg a "$_dw_ru_arch" '
    (.targets[$p] // null) as $target
    | if $target == null or ($target.architectures[$a] // null) == null then empty
      else (($target | del(.architectures)) + $target.architectures[$a])
      end
  ' "$RUSTUP_ARTIFACT_MANIFEST"
}

rustup_artifact_glibc_available() {
  have getconf || return 1
  getconf GNU_LIBC_VERSION >/dev/null 2>&1
}

rustup_artifact_target_compatible() {
  _dw_ru_platform=$1
  _dw_ru_arch=$2
  [ -n "$(rustup_artifact_target_json "$_dw_ru_platform" "$_dw_ru_arch" || true)" ] || return 1
  [ "$_dw_ru_platform" != linux ] || rustup_artifact_glibc_available
}

rustup_artifact_triple() {
  _dw_ru_target=$(rustup_artifact_target_json "$1" "$2")
  [ -n "$_dw_ru_target" ] || return 1
  printf '%s' "$_dw_ru_target" | jq -r '.triple'
}

rustup_artifact_source_url() {
  _dw_ru_platform=$1
  _dw_ru_arch=$2
  _dw_ru_target=$(rustup_artifact_target_json "$_dw_ru_platform" "$_dw_ru_arch")
  [ -n "$_dw_ru_target" ] || return 1
  _dw_ru_base=$(jq -r '.source_base' "$RUSTUP_ARTIFACT_MANIFEST")
  [ "$_dw_ru_base" = 'https://static.rust-lang.org/rustup/dist' ] || return 1
  _dw_ru_triple=$(printf '%s' "$_dw_ru_target" | jq -r '.triple')
  _dw_ru_binary=$(printf '%s' "$_dw_ru_target" | jq -r '.binary_name')
  case "$_dw_ru_triple" in *[!A-Za-z0-9_-]*) return 1 ;; esac
  [ "$_dw_ru_binary" = rustup-init ] || return 1
  printf '%s/%s/%s' "$_dw_ru_base" "$_dw_ru_triple" "$_dw_ru_binary"
}

rustup_artifact_checksum_url() {
  _dw_ru_source=$(rustup_artifact_source_url "$1" "$2") || return 1
  _dw_ru_suffix=$(jq -r '.checksum_suffix' "$RUSTUP_ARTIFACT_MANIFEST")
  [ "$_dw_ru_suffix" = .sha256 ] || return 1
  printf '%s%s' "$_dw_ru_source" "$_dw_ru_suffix"
}

rustup_artifact_state_ready() {
  [ ! -L "$STATE_DIR" ] || return 1
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  [ -d "$STATE_DIR" ] && [ -w "$STATE_DIR" ] || return 1
  _dw_ru_state="$STATE_DIR/rustup-artifact.jsonl"
  [ ! -L "$_dw_ru_state" ] || return 1
  if [ -e "$_dw_ru_state" ]; then [ -f "$_dw_ru_state" ] && [ -w "$_dw_ru_state" ] || return 1; fi
}

rustup_artifact_record_state() {
  _dw_ru_action=$1
  _dw_ru_platform=$2
  _dw_ru_arch=$3
  _dw_ru_triple=$4
  _dw_ru_source=$5
  _dw_ru_installer_sha=$6
  _dw_ru_cargo_home=$7
  _dw_ru_rustup_home=$8
  _dw_ru_created=$9
  rustup_artifact_state_ready || die "GATE-10 rustup state path is not safely writable: $STATE_DIR"
  _dw_ru_timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  jq -nc --arg timestamp "$_dw_ru_timestamp" --arg action "$_dw_ru_action" --arg platform "$_dw_ru_platform" --arg architecture "$_dw_ru_arch" \
    --arg triple "$_dw_ru_triple" --arg source_url "$_dw_ru_source" --arg installer_sha256 "$_dw_ru_installer_sha" \
    --arg cargo_home "$_dw_ru_cargo_home" --arg rustup_home "$_dw_ru_rustup_home" --argjson created "$_dw_ru_created" \
    '{timestamp:$timestamp,environment:"rust",publisher:"The Rust Project Developers",action:$action,platform:$platform,architecture:$architecture,target_triple:$triple,source_url:$source_url,installer_sha256:$installer_sha256,cargo_home:$cargo_home,rustup_home:$rustup_home,created:$created,path_mutation:false,privileged:false}' \
    >> "$STATE_DIR/rustup-artifact.jsonl"
}

rustup_artifact_assert_parent() {
  _dw_ru_parent=$1
  [ -d "$_dw_ru_parent" ] || die "GATE-08 rustup parent must already exist: $_dw_ru_parent"
  [ ! -L "$_dw_ru_parent" ] || die "GATE-08 rustup parent is a symlink: $_dw_ru_parent"
  [ -w "$_dw_ru_parent" ] || die "GATE-08 rustup parent is not writable: $_dw_ru_parent"
}

rustup_artifact_assert_path_declared() {
  _dw_ru_path=$1
  case ":${PATH:-}:" in *":$_dw_ru_path:"*) return 0 ;; esac
  die "GATE-13 PATH must already contain $_dw_ru_path; devkit-wulf will not modify PATH implicitly"
}

rustup_artifact_binary_hash() {
  _dw_ru_cargo_home=$1
  _dw_ru_name=$2
  _dw_ru_file="$_dw_ru_cargo_home/bin/$_dw_ru_name"
  [ -f "$_dw_ru_file" ] && [ ! -L "$_dw_ru_file" ] && [ -x "$_dw_ru_file" ] || return 1
  _dw_ru_sha=$(sha256_file "$_dw_ru_file")
  [ "$_dw_ru_sha" != unavailable ] || return 1
  printf '%s' "$_dw_ru_sha"
}

verify_rustup_artifact() {
  _dw_ru_platform=$1
  _dw_ru_arch=$2
  rustup_artifact_target_compatible "$_dw_ru_platform" "$_dw_ru_arch" || return 1
  _dw_ru_cargo_home=$(rustup_artifact_cargo_home) || return 1
  _dw_ru_rustup_home=$(rustup_artifact_rustup_home) || return 1
  _dw_ru_marker=$(rustup_artifact_marker) || return 1
  [ -d "$_dw_ru_cargo_home" ] && [ ! -L "$_dw_ru_cargo_home" ] || return 1
  [ -d "$_dw_ru_rustup_home" ] && [ ! -L "$_dw_ru_rustup_home" ] || return 1
  [ -f "$_dw_ru_marker" ] && [ ! -L "$_dw_ru_marker" ] || return 1
  _dw_ru_triple=$(rustup_artifact_triple "$_dw_ru_platform" "$_dw_ru_arch") || return 1
  _dw_ru_source=$(rustup_artifact_source_url "$_dw_ru_platform" "$_dw_ru_arch") || return 1
  jq -e --arg p "$_dw_ru_platform" --arg a "$_dw_ru_arch" --arg t "$_dw_ru_triple" --arg s "$_dw_ru_source" '
    .environment == "rust" and .publisher == "The Rust Project Developers" and .platform == $p and
    .architecture == $a and .target_triple == $t and .source_url == $s and
    (.installer_sha256 | test("^[0-9a-fA-F]{64}$"))
  ' "$_dw_ru_marker" >/dev/null 2>&1 || return 1
  for _dw_ru_name in rustup rustc cargo; do
    _dw_ru_sha=$(rustup_artifact_binary_hash "$_dw_ru_cargo_home" "$_dw_ru_name") || return 1
    jq -e --arg n "$_dw_ru_name" --arg h "$_dw_ru_sha" '.managed_binaries[$n] == $h' "$_dw_ru_marker" >/dev/null 2>&1 || return 1
  done
  CARGO_HOME="$_dw_ru_cargo_home" RUSTUP_HOME="$_dw_ru_rustup_home" "$_dw_ru_cargo_home/bin/rustup" --version >/dev/null 2>&1 || return 1
  CARGO_HOME="$_dw_ru_cargo_home" RUSTUP_HOME="$_dw_ru_rustup_home" "$_dw_ru_cargo_home/bin/rustc" --version >/dev/null 2>&1 || return 1
  CARGO_HOME="$_dw_ru_cargo_home" RUSTUP_HOME="$_dw_ru_rustup_home" "$_dw_ru_cargo_home/bin/cargo" --version >/dev/null 2>&1 || return 1
}

plan_rustup_artifact() {
  _dw_ru_platform=$1
  _dw_ru_arch=$2
  rustup_artifact_target_compatible "$_dw_ru_platform" "$_dw_ru_arch" || return 1
  _dw_ru_cargo_home=$(rustup_artifact_cargo_home) || return 1
  _dw_ru_rustup_home=$(rustup_artifact_rustup_home) || return 1
  _dw_ru_path=$(rustup_artifact_path_dir) || return 1
  _dw_ru_triple=$(rustup_artifact_triple "$_dw_ru_platform" "$_dw_ru_arch") || return 1
  _dw_ru_source=$(rustup_artifact_source_url "$_dw_ru_platform" "$_dw_ru_arch") || return 1
  _dw_ru_checksum=$(rustup_artifact_checksum_url "$_dw_ru_platform" "$_dw_ru_arch") || return 1
  printf 'rustup_artifact:\n'
  printf '  publisher: The Rust Project Developers\n'
  printf '  target_triple: %s\n' "$_dw_ru_triple"
  printf '  url: %s\n' "$_dw_ru_source"
  printf '  checksum_url: %s\n' "$_dw_ru_checksum"
  printf '  integrity: sha256\n'
  printf '  cargo_home: %s\n' "$_dw_ru_cargo_home"
  printf '  rustup_home: %s\n' "$_dw_ru_rustup_home"
  printf '  path_directory: %s\n' "$_dw_ru_path"
  printf '  profile: minimal\n'
  printf '  default_toolchain: stable\n'
  printf '  remote_script_execution: false\n'
  printf '  path_mutation: none\n'
  printf '  privilege: none\n'
  printf '  mutates_host: false\n'
}

rustup_artifact_write_marker() {
  _dw_ru_marker=$1
  _dw_ru_platform=$2
  _dw_ru_arch=$3
  _dw_ru_triple=$4
  _dw_ru_source=$5
  _dw_ru_installer_sha=$6
  _dw_ru_cargo_home=$7
  _dw_ru_rustup_home=$8
  _dw_ru_rustup_sha=$(rustup_artifact_binary_hash "$_dw_ru_cargo_home" rustup) || return 1
  _dw_ru_rustc_sha=$(rustup_artifact_binary_hash "$_dw_ru_cargo_home" rustc) || return 1
  _dw_ru_cargo_sha=$(rustup_artifact_binary_hash "$_dw_ru_cargo_home" cargo) || return 1
  _dw_ru_tmp="$_dw_ru_marker.tmp.$$"
  [ ! -e "$_dw_ru_tmp" ] && [ ! -L "$_dw_ru_tmp" ] || return 1
  jq -nc --arg p "$_dw_ru_platform" --arg a "$_dw_ru_arch" --arg t "$_dw_ru_triple" --arg s "$_dw_ru_source" --arg i "$_dw_ru_installer_sha" \
    --arg cargo_home "$_dw_ru_cargo_home" --arg rustup_home "$_dw_ru_rustup_home" --arg rustup_sha "$_dw_ru_rustup_sha" --arg rustc_sha "$_dw_ru_rustc_sha" --arg cargo_sha "$_dw_ru_cargo_sha" \
    '{environment:"rust",publisher:"The Rust Project Developers",platform:$p,architecture:$a,target_triple:$t,source_url:$s,installer_sha256:$i,cargo_home:$cargo_home,rustup_home:$rustup_home,managed_binaries:{rustup:$rustup_sha,rustc:$rustc_sha,cargo:$cargo_sha}}' > "$_dw_ru_tmp" || return 1
  mv "$_dw_ru_tmp" "$_dw_ru_marker"
}

install_rustup_artifact() (
  set -eu
  _dw_ru_platform=$1
  _dw_ru_arch=$2
  rustup_artifact_target_compatible "$_dw_ru_platform" "$_dw_ru_arch" || die "no compatible verified rustup artifact for $_dw_ru_platform/$_dw_ru_arch"
  _dw_ru_cargo_home=$(rustup_artifact_cargo_home) || die "invalid rustup cargo home"
  _dw_ru_rustup_home=$(rustup_artifact_rustup_home) || die "invalid rustup home"
  _dw_ru_path=$(rustup_artifact_path_dir) || die "invalid rustup PATH directory"
  _dw_ru_marker=$(rustup_artifact_marker) || die "invalid rustup marker path"
  _dw_ru_root=$(dirname "$_dw_ru_cargo_home")
  _dw_ru_local_share=$(dirname "$_dw_ru_root")
  rustup_artifact_assert_parent "$_dw_ru_local_share"
  if [ ! -e "$_dw_ru_root" ]; then mkdir "$_dw_ru_root" || die "unable to create devkit-wulf user data root"; fi
  [ -d "$_dw_ru_root" ] && [ ! -L "$_dw_ru_root" ] && [ -w "$_dw_ru_root" ] || die "GATE-08 devkit-wulf user data root is unsafe: $_dw_ru_root"
  rustup_artifact_assert_path_declared "$_dw_ru_path"
  rustup_artifact_state_ready || die "GATE-10 rustup state path is not safely writable: $STATE_DIR"

  if [ -e "$_dw_ru_cargo_home" ] || [ -L "$_dw_ru_cargo_home" ] || [ -e "$_dw_ru_rustup_home" ] || [ -L "$_dw_ru_rustup_home" ]; then
    [ ! -L "$_dw_ru_cargo_home" ] && [ ! -L "$_dw_ru_rustup_home" ] || die "GATE-08 rustup managed home is a symlink"
    if verify_rustup_artifact "$_dw_ru_platform" "$_dw_ru_arch"; then
      _dw_ru_triple=$(rustup_artifact_triple "$_dw_ru_platform" "$_dw_ru_arch")
      _dw_ru_source=$(rustup_artifact_source_url "$_dw_ru_platform" "$_dw_ru_arch")
      _dw_ru_installer_sha=$(jq -r '.installer_sha256' "$_dw_ru_marker")
      rustup_artifact_record_state observed-managed "$_dw_ru_platform" "$_dw_ru_arch" "$_dw_ru_triple" "$_dw_ru_source" "$_dw_ru_installer_sha" "$_dw_ru_cargo_home" "$_dw_ru_rustup_home" false
      exit 0
    fi
    die "GATE-08 existing rustup/cargo homes are not an exact devkit-wulf-managed installation"
  fi

  _dw_ru_triple=$(rustup_artifact_triple "$_dw_ru_platform" "$_dw_ru_arch")
  _dw_ru_source=$(rustup_artifact_source_url "$_dw_ru_platform" "$_dw_ru_arch")
  _dw_ru_checksum=$(rustup_artifact_checksum_url "$_dw_ru_platform" "$_dw_ru_arch")
  _dw_ru_init=$(mktemp "${TMPDIR:-/tmp}/devkit-wulf-rustup-init.XXXXXX") || die "unable to create rustup-init staging file"
  _dw_ru_sha_file=$(mktemp "${TMPDIR:-/tmp}/devkit-wulf-rustup-sha.XXXXXX") || { rm -f "$_dw_ru_init"; die "unable to create rustup checksum staging file"; }
  trap 'rm -f "$_dw_ru_init" "$_dw_ru_sha_file"' EXIT HUP INT TERM
  download_https "$_dw_ru_checksum" "$_dw_ru_sha_file"
  _dw_ru_expected=$(awk 'NR==1 {print $1}' "$_dw_ru_sha_file" | tr 'A-F' 'a-f')
  printf '%s\n' "$_dw_ru_expected" | grep -Eq '^[0-9a-f]{64}$' || die "GATE-05 rustup checksum endpoint returned malformed SHA-256"
  download_https "$_dw_ru_source" "$_dw_ru_init"
  _dw_ru_actual=$(sha256_file "$_dw_ru_init" | tr 'A-F' 'a-f')
  [ "$_dw_ru_actual" != unavailable ] || die "GATE-05 requires a local SHA-256 implementation"
  [ "$_dw_ru_actual" = "$_dw_ru_expected" ] || die "GATE-05 rustup-init SHA-256 mismatch"
  chmod 0755 "$_dw_ru_init" || die "unable to make verified rustup-init executable"

  rustup_artifact_record_state mutation-intent "$_dw_ru_platform" "$_dw_ru_arch" "$_dw_ru_triple" "$_dw_ru_source" "$_dw_ru_actual" "$_dw_ru_cargo_home" "$_dw_ru_rustup_home" false
  if CARGO_HOME="$_dw_ru_cargo_home" RUSTUP_HOME="$_dw_ru_rustup_home" "$_dw_ru_init" -y --profile minimal --default-toolchain stable --no-modify-path; then :; else
    rustup_artifact_record_state environment-incomplete "$_dw_ru_platform" "$_dw_ru_arch" "$_dw_ru_triple" "$_dw_ru_source" "$_dw_ru_actual" "$_dw_ru_cargo_home" "$_dw_ru_rustup_home" false
    die "rustup-init failed; partial user-scoped state was retained for inspection"
  fi
  for _dw_ru_name in rustup rustc cargo; do rustup_artifact_binary_hash "$_dw_ru_cargo_home" "$_dw_ru_name" >/dev/null || die "GATE-12 managed $_dw_ru_name is missing after rustup-init"; done
  CARGO_HOME="$_dw_ru_cargo_home" RUSTUP_HOME="$_dw_ru_rustup_home" "$_dw_ru_cargo_home/bin/rustup" --version >/dev/null 2>&1 || die "GATE-12 rustup --version failed"
  CARGO_HOME="$_dw_ru_cargo_home" RUSTUP_HOME="$_dw_ru_rustup_home" "$_dw_ru_cargo_home/bin/rustc" --version >/dev/null 2>&1 || die "GATE-12 rustc --version failed"
  CARGO_HOME="$_dw_ru_cargo_home" RUSTUP_HOME="$_dw_ru_rustup_home" "$_dw_ru_cargo_home/bin/cargo" --version >/dev/null 2>&1 || die "GATE-12 cargo --version failed"
  rustup_artifact_write_marker "$_dw_ru_marker" "$_dw_ru_platform" "$_dw_ru_arch" "$_dw_ru_triple" "$_dw_ru_source" "$_dw_ru_actual" "$_dw_ru_cargo_home" "$_dw_ru_rustup_home" || die "unable to write rustup ownership marker"
  verify_rustup_artifact "$_dw_ru_platform" "$_dw_ru_arch" || die "GATE-12 managed rustup verification failed"
  rustup_artifact_record_state installed-verified "$_dw_ru_platform" "$_dw_ru_arch" "$_dw_ru_triple" "$_dw_ru_source" "$_dw_ru_actual" "$_dw_ru_cargo_home" "$_dw_ru_rustup_home" true
  rm -f "$_dw_ru_init" "$_dw_ru_sha_file"
  trap - EXIT HUP INT TERM
)

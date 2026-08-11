#!/bin/sh
# Verified rustup-init artifact helper.
# Caller contract: jq, have, die, download_https, sha256_file,
# STATE_DIR and RUSTUP_ARTIFACT_MANIFEST.

rustup_artifact_expand_home() {
  template=$1
  case "$template" in '{home}/'*) ;; *) return 1 ;; esac
  [ -n "${HOME:-}" ] || return 1
  case "$HOME" in /*) ;; *) return 1 ;; esac
  suffix=${template#\{home\}}
  case "$suffix" in *'/../'*|'/..'|*'/..') return 1 ;; esac
  printf '%s%s' "$HOME" "$suffix"
}

rustup_artifact_cargo_home() { rustup_artifact_expand_home "$(jq -r '.install.cargo_home_template' "$RUSTUP_ARTIFACT_MANIFEST")"; }
rustup_artifact_rustup_home() { rustup_artifact_expand_home "$(jq -r '.install.rustup_home_template' "$RUSTUP_ARTIFACT_MANIFEST")"; }
rustup_artifact_path_dir() { rustup_artifact_expand_home "$(jq -r '.install.path_directory_template' "$RUSTUP_ARTIFACT_MANIFEST")"; }
rustup_artifact_marker() { rustup_artifact_expand_home "$(jq -r '.install.marker_template' "$RUSTUP_ARTIFACT_MANIFEST")"; }

rustup_artifact_target_json() {
  platform=$1 arch=$2
  jq -c --arg p "$platform" --arg a "$arch" '
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
  platform=$1 arch=$2
  [ -n "$(rustup_artifact_target_json "$platform" "$arch" || true)" ] || return 1
  [ "$platform" != linux ] || rustup_artifact_glibc_available
}

rustup_artifact_triple() {
  target=$(rustup_artifact_target_json "$1" "$2")
  [ -n "$target" ] || return 1
  printf '%s' "$target" | jq -r '.triple'
}

rustup_artifact_source_url() {
  platform=$1 arch=$2
  target=$(rustup_artifact_target_json "$platform" "$arch")
  [ -n "$target" ] || return 1
  base=$(jq -r '.source_base' "$RUSTUP_ARTIFACT_MANIFEST")
  [ "$base" = 'https://static.rust-lang.org/rustup/dist' ] || return 1
  triple=$(printf '%s' "$target" | jq -r '.triple')
  binary=$(printf '%s' "$target" | jq -r '.binary_name')
  case "$triple" in *[!A-Za-z0-9_-]*) return 1 ;; esac
  [ "$binary" = rustup-init ] || return 1
  printf '%s/%s/%s' "$base" "$triple" "$binary"
}

rustup_artifact_checksum_url() {
  source=$(rustup_artifact_source_url "$1" "$2") || return 1
  suffix=$(jq -r '.checksum_suffix' "$RUSTUP_ARTIFACT_MANIFEST")
  [ "$suffix" = .sha256 ] || return 1
  printf '%s%s' "$source" "$suffix"
}

rustup_artifact_state_ready() {
  [ ! -L "$STATE_DIR" ] || return 1
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  [ -d "$STATE_DIR" ] && [ -w "$STATE_DIR" ] || return 1
  state="$STATE_DIR/rustup-artifact.jsonl"
  [ ! -L "$state" ] || return 1
  if [ -e "$state" ]; then [ -f "$state" ] && [ -w "$state" ] || return 1; fi
}

rustup_artifact_record_state() {
  action=$1 platform=$2 arch=$3 triple=$4 source=$5 installer_sha=$6 cargo_home=$7 rustup_home=$8 created=$9
  rustup_artifact_state_ready || die "GATE-10 rustup state path is not safely writable: $STATE_DIR"
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  jq -nc --arg timestamp "$timestamp" --arg action "$action" --arg platform "$platform" --arg architecture "$arch" \
    --arg triple "$triple" --arg source_url "$source" --arg installer_sha256 "$installer_sha" \
    --arg cargo_home "$cargo_home" --arg rustup_home "$rustup_home" --argjson created "$created" \
    '{timestamp:$timestamp,environment:"rust",publisher:"The Rust Project Developers",action:$action,platform:$platform,architecture:$architecture,target_triple:$triple,source_url:$source_url,installer_sha256:$installer_sha256,cargo_home:$cargo_home,rustup_home:$rustup_home,created:$created,path_mutation:false,privileged:false}' \
    >> "$STATE_DIR/rustup-artifact.jsonl"
}

rustup_artifact_assert_parent() {
  parent=$1
  [ -d "$parent" ] || die "GATE-08 rustup parent must already exist: $parent"
  [ ! -L "$parent" ] || die "GATE-08 rustup parent is a symlink: $parent"
  [ -w "$parent" ] || die "GATE-08 rustup parent is not writable: $parent"
}

rustup_artifact_assert_path_declared() {
  path_dir=$1
  case ":${PATH:-}:" in *":$path_dir:"*) return 0 ;; esac
  die "GATE-13 PATH must already contain $path_dir; devkit-wulf will not modify PATH implicitly"
}

rustup_artifact_binary_hash() {
  cargo_home=$1 name=$2
  file="$cargo_home/bin/$name"
  [ -f "$file" ] && [ ! -L "$file" ] && [ -x "$file" ] || return 1
  sha=$(sha256_file "$file")
  [ "$sha" != unavailable ] || return 1
  printf '%s' "$sha"
}

verify_rustup_artifact() {
  platform=$1 arch=$2
  rustup_artifact_target_compatible "$platform" "$arch" || return 1
  cargo_home=$(rustup_artifact_cargo_home) || return 1
  rustup_home=$(rustup_artifact_rustup_home) || return 1
  marker=$(rustup_artifact_marker) || return 1
  [ -d "$cargo_home" ] && [ ! -L "$cargo_home" ] || return 1
  [ -d "$rustup_home" ] && [ ! -L "$rustup_home" ] || return 1
  [ -f "$marker" ] && [ ! -L "$marker" ] || return 1
  triple=$(rustup_artifact_triple "$platform" "$arch") || return 1
  source=$(rustup_artifact_source_url "$platform" "$arch") || return 1
  jq -e --arg p "$platform" --arg a "$arch" --arg t "$triple" --arg s "$source" '
    .environment == "rust" and .publisher == "The Rust Project Developers" and .platform == $p and
    .architecture == $a and .target_triple == $t and .source_url == $s and
    (.installer_sha256 | test("^[0-9a-fA-F]{64}$"))
  ' "$marker" >/dev/null 2>&1 || return 1
  for name in rustup rustc cargo; do
    sha=$(rustup_artifact_binary_hash "$cargo_home" "$name") || return 1
    jq -e --arg n "$name" --arg h "$sha" '.managed_binaries[$n] == $h' "$marker" >/dev/null 2>&1 || return 1
  done
  CARGO_HOME="$cargo_home" RUSTUP_HOME="$rustup_home" "$cargo_home/bin/rustup" --version >/dev/null 2>&1 || return 1
  CARGO_HOME="$cargo_home" RUSTUP_HOME="$rustup_home" "$cargo_home/bin/rustc" --version >/dev/null 2>&1 || return 1
  CARGO_HOME="$cargo_home" RUSTUP_HOME="$rustup_home" "$cargo_home/bin/cargo" --version >/dev/null 2>&1 || return 1
}

plan_rustup_artifact() {
  platform=$1 arch=$2
  rustup_artifact_target_compatible "$platform" "$arch" || return 1
  cargo_home=$(rustup_artifact_cargo_home) || return 1
  rustup_home=$(rustup_artifact_rustup_home) || return 1
  path_dir=$(rustup_artifact_path_dir) || return 1
  triple=$(rustup_artifact_triple "$platform" "$arch") || return 1
  source=$(rustup_artifact_source_url "$platform" "$arch") || return 1
  checksum=$(rustup_artifact_checksum_url "$platform" "$arch") || return 1
  printf 'rustup_artifact:\n'
  printf '  publisher: The Rust Project Developers\n'
  printf '  target_triple: %s\n' "$triple"
  printf '  url: %s\n' "$source"
  printf '  checksum_url: %s\n' "$checksum"
  printf '  integrity: sha256\n'
  printf '  cargo_home: %s\n' "$cargo_home"
  printf '  rustup_home: %s\n' "$rustup_home"
  printf '  path_directory: %s\n' "$path_dir"
  printf '  profile: minimal\n'
  printf '  default_toolchain: stable\n'
  printf '  remote_script_execution: false\n'
  printf '  path_mutation: none\n'
  printf '  privilege: none\n'
  printf '  mutates_host: false\n'
}

rustup_artifact_write_marker() {
  marker=$1 platform=$2 arch=$3 triple=$4 source=$5 installer_sha=$6 cargo_home=$7 rustup_home=$8
  rustup_sha=$(rustup_artifact_binary_hash "$cargo_home" rustup) || return 1
  rustc_sha=$(rustup_artifact_binary_hash "$cargo_home" rustc) || return 1
  cargo_sha=$(rustup_artifact_binary_hash "$cargo_home" cargo) || return 1
  tmp="$marker.tmp.$$"
  [ ! -e "$tmp" ] && [ ! -L "$tmp" ] || return 1
  jq -nc --arg p "$platform" --arg a "$arch" --arg t "$triple" --arg s "$source" --arg i "$installer_sha" \
    --arg cargo_home "$cargo_home" --arg rustup_home "$rustup_home" --arg rustup_sha "$rustup_sha" --arg rustc_sha "$rustc_sha" --arg cargo_sha "$cargo_sha" \
    '{environment:"rust",publisher:"The Rust Project Developers",platform:$p,architecture:$a,target_triple:$t,source_url:$s,installer_sha256:$i,cargo_home:$cargo_home,rustup_home:$rustup_home,managed_binaries:{rustup:$rustup_sha,rustc:$rustc_sha,cargo:$cargo_sha}}' > "$tmp" || return 1
  mv "$tmp" "$marker"
}

install_rustup_artifact() (
  set -eu
  platform=$1 arch=$2
  rustup_artifact_target_compatible "$platform" "$arch" || die "no compatible verified rustup artifact for $platform/$arch"
  cargo_home=$(rustup_artifact_cargo_home) || die "invalid rustup cargo home"
  rustup_home=$(rustup_artifact_rustup_home) || die "invalid rustup home"
  path_dir=$(rustup_artifact_path_dir) || die "invalid rustup PATH directory"
  marker=$(rustup_artifact_marker) || die "invalid rustup marker path"
  root=$(dirname "$cargo_home")
  local_share=$(dirname "$root")
  rustup_artifact_assert_parent "$local_share"
  if [ ! -e "$root" ]; then mkdir "$root" || die "unable to create devkit-wulf user data root"; fi
  [ -d "$root" ] && [ ! -L "$root" ] && [ -w "$root" ] || die "GATE-08 devkit-wulf user data root is unsafe: $root"
  rustup_artifact_assert_path_declared "$path_dir"
  rustup_artifact_state_ready || die "GATE-10 rustup state path is not safely writable: $STATE_DIR"

  if [ -e "$cargo_home" ] || [ -L "$cargo_home" ] || [ -e "$rustup_home" ] || [ -L "$rustup_home" ]; then
    [ ! -L "$cargo_home" ] && [ ! -L "$rustup_home" ] || die "GATE-08 rustup managed home is a symlink"
    if verify_rustup_artifact "$platform" "$arch"; then
      triple=$(rustup_artifact_triple "$platform" "$arch")
      source=$(rustup_artifact_source_url "$platform" "$arch")
      installer_sha=$(jq -r '.installer_sha256' "$marker")
      rustup_artifact_record_state observed-managed "$platform" "$arch" "$triple" "$source" "$installer_sha" "$cargo_home" "$rustup_home" false
      exit 0
    fi
    die "GATE-08 existing rustup/cargo homes are not an exact devkit-wulf-managed installation"
  fi

  triple=$(rustup_artifact_triple "$platform" "$arch")
  source=$(rustup_artifact_source_url "$platform" "$arch")
  checksum=$(rustup_artifact_checksum_url "$platform" "$arch")
  init=$(mktemp "${TMPDIR:-/tmp}/devkit-wulf-rustup-init.XXXXXX") || die "unable to create rustup-init staging file"
  sha_file=$(mktemp "${TMPDIR:-/tmp}/devkit-wulf-rustup-sha.XXXXXX") || { rm -f "$init"; die "unable to create rustup checksum staging file"; }
  trap 'rm -f "$init" "$sha_file"' EXIT HUP INT TERM
  download_https "$checksum" "$sha_file"
  expected=$(awk 'NR==1 {print $1}' "$sha_file" | tr 'A-F' 'a-f')
  printf '%s\n' "$expected" | grep -Eq '^[0-9a-f]{64}$' || die "GATE-05 rustup checksum endpoint returned malformed SHA-256"
  download_https "$source" "$init"
  actual=$(sha256_file "$init" | tr 'A-F' 'a-f')
  [ "$actual" != unavailable ] || die "GATE-05 requires a local SHA-256 implementation"
  [ "$actual" = "$expected" ] || die "GATE-05 rustup-init SHA-256 mismatch"
  chmod 0755 "$init" || die "unable to make verified rustup-init executable"

  rustup_artifact_record_state mutation-intent "$platform" "$arch" "$triple" "$source" "$actual" "$cargo_home" "$rustup_home" false
  if CARGO_HOME="$cargo_home" RUSTUP_HOME="$rustup_home" "$init" -y --profile minimal --default-toolchain stable --no-modify-path; then :; else
    rustup_artifact_record_state environment-incomplete "$platform" "$arch" "$triple" "$source" "$actual" "$cargo_home" "$rustup_home" false
    die "rustup-init failed; partial user-scoped state was retained for inspection"
  fi
  for name in rustup rustc cargo; do rustup_artifact_binary_hash "$cargo_home" "$name" >/dev/null || die "GATE-12 managed $name is missing after rustup-init"; done
  CARGO_HOME="$cargo_home" RUSTUP_HOME="$rustup_home" "$cargo_home/bin/rustup" --version >/dev/null 2>&1 || die "GATE-12 rustup --version failed"
  CARGO_HOME="$cargo_home" RUSTUP_HOME="$rustup_home" "$cargo_home/bin/rustc" --version >/dev/null 2>&1 || die "GATE-12 rustc --version failed"
  CARGO_HOME="$cargo_home" RUSTUP_HOME="$rustup_home" "$cargo_home/bin/cargo" --version >/dev/null 2>&1 || die "GATE-12 cargo --version failed"
  rustup_artifact_write_marker "$marker" "$platform" "$arch" "$triple" "$source" "$actual" "$cargo_home" "$rustup_home" || die "unable to write rustup ownership marker"
  verify_rustup_artifact "$platform" "$arch" || die "GATE-12 managed rustup verification failed"
  rustup_artifact_record_state installed-verified "$platform" "$arch" "$triple" "$source" "$actual" "$cargo_home" "$rustup_home" true
  rm -f "$init" "$sha_file"
  trap - EXIT HUP INT TERM
)

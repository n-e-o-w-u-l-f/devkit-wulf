#!/bin/sh
# Shared POSIX environment-level checks layered over lib/artifacts.sh.
# Caller provides: die, sha256_file, install_verified_artifact,
# ARTIFACT_MANIFEST, STATE_DIR and HOME.

flutter_stable_destination() {
  [ -n "${HOME:-}" ] || return 1
  case "$HOME" in /*) ;; *) return 1 ;; esac
  printf '%s/develop/flutter' "$HOME"
}

flutter_stable_marker_valid() {
  _dw_fs_root=$1
  _dw_fs_platform=$2
  _dw_fs_marker="$_dw_fs_root/.devkit-wulf-artifact.json"
  [ -d "$_dw_fs_root" ] && [ ! -L "$_dw_fs_root" ] || return 1
  [ -d "$_dw_fs_root/bin" ] && [ ! -L "$_dw_fs_root/bin" ] || return 1
  [ -f "$_dw_fs_marker" ] && [ ! -L "$_dw_fs_marker" ] || return 1
  case "$_dw_fs_platform" in linux|macos) ;; *) return 1 ;; esac
  jq -e --arg p "$_dw_fs_platform" '
    .environment == "flutter"
    and (.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+([._+-][A-Za-z0-9.-]+)?$"))
    and (.source_url | type == "string" and startswith("https://storage.googleapis.com/flutter_infra_release/releases/") and contains("/stable/" + $p + "/"))
    and (.sha256 | type == "string" and test("^[0-9a-fA-F]{64}$"))
    and (.critical_files["bin/flutter"] | type == "string" and test("^[0-9a-fA-F]{64}$"))
    and (.critical_files["bin/dart"] | type == "string" and test("^[0-9a-fA-F]{64}$"))
  ' "$_dw_fs_marker" >/dev/null 2>&1
}

flutter_stable_write_critical_hashes() {
  _dw_fs_root=$1
  _dw_fs_marker="$_dw_fs_root/.devkit-wulf-artifact.json"
  [ -d "$_dw_fs_root/bin" ] && [ ! -L "$_dw_fs_root/bin" ] || die "managed Flutter bin directory is missing or unsafe"
  [ -f "$_dw_fs_marker" ] && [ ! -L "$_dw_fs_marker" ] || die "Flutter ownership marker is missing or unsafe"
  [ -x "$_dw_fs_root/bin/flutter" ] && [ ! -L "$_dw_fs_root/bin/flutter" ] || die "managed Flutter executable is missing or unsafe"
  [ -x "$_dw_fs_root/bin/dart" ] && [ ! -L "$_dw_fs_root/bin/dart" ] || die "managed Dart executable is missing or unsafe"
  _dw_fs_flutter=$(sha256_file "$_dw_fs_root/bin/flutter" | tr 'A-F' 'a-f')
  _dw_fs_dart=$(sha256_file "$_dw_fs_root/bin/dart" | tr 'A-F' 'a-f')
  printf '%s\n' "$_dw_fs_flutter" | grep -Eq '^[0-9a-f]{64}$' || die "unable to hash managed Flutter launcher"
  printf '%s\n' "$_dw_fs_dart" | grep -Eq '^[0-9a-f]{64}$' || die "unable to hash managed Dart launcher"
  _dw_fs_tmp="$_dw_fs_marker.tmp.$$"
  [ ! -e "$_dw_fs_tmp" ] && [ ! -L "$_dw_fs_tmp" ] || die "refusing existing Flutter marker staging file"
  jq --arg f "$_dw_fs_flutter" --arg d "$_dw_fs_dart" '. + {critical_files:{"bin/flutter":$f,"bin/dart":$d}}' "$_dw_fs_marker" > "$_dw_fs_tmp" \
    || { rm -f "$_dw_fs_tmp"; die "unable to enrich Flutter ownership marker"; }
  mv "$_dw_fs_tmp" "$_dw_fs_marker" || die "unable to atomically update Flutter ownership marker"
}

verify_flutter_stable_managed() {
  _dw_fs_platform=$1
  _dw_fs_root=$(flutter_stable_destination) || return 1
  flutter_stable_marker_valid "$_dw_fs_root" "$_dw_fs_platform" || return 1
  _dw_fs_marker="$_dw_fs_root/.devkit-wulf-artifact.json"
  [ -x "$_dw_fs_root/bin/flutter" ] && [ ! -L "$_dw_fs_root/bin/flutter" ] || return 1
  [ -x "$_dw_fs_root/bin/dart" ] && [ ! -L "$_dw_fs_root/bin/dart" ] || return 1
  _dw_fs_expected_flutter=$(jq -r '.critical_files["bin/flutter"]' "$_dw_fs_marker")
  _dw_fs_expected_dart=$(jq -r '.critical_files["bin/dart"]' "$_dw_fs_marker")
  _dw_fs_actual_flutter=$(sha256_file "$_dw_fs_root/bin/flutter" | tr 'A-F' 'a-f')
  _dw_fs_actual_dart=$(sha256_file "$_dw_fs_root/bin/dart" | tr 'A-F' 'a-f')
  [ "$_dw_fs_actual_flutter" = "$(printf '%s' "$_dw_fs_expected_flutter" | tr 'A-F' 'a-f')" ] || return 1
  [ "$_dw_fs_actual_dart" = "$(printf '%s' "$_dw_fs_expected_dart" | tr 'A-F' 'a-f')" ] || return 1
  "$_dw_fs_root/bin/flutter" --version >/dev/null 2>&1 || return 1
  "$_dw_fs_root/bin/dart" --version >/dev/null 2>&1 || return 1
  return 0
}

install_flutter_stable_managed() {
  _dw_fs_platform=$1
  _dw_fs_family=$2
  _dw_fs_arch=$3
  _dw_fs_root=$(flutter_stable_destination) || die "unable to resolve Flutter destination"

  if [ -e "$_dw_fs_root" ] || [ -L "$_dw_fs_root" ]; then
    verify_flutter_stable_managed "$_dw_fs_platform" && return 0
    die "GATE-08 existing Flutter SDK is not an exact selector-managed installation; explicit migration/reinstall is required"
  fi

  install_verified_artifact flutter "$_dw_fs_platform" "$_dw_fs_family" "$_dw_fs_arch"
  flutter_stable_write_critical_hashes "$_dw_fs_root"
  verify_flutter_stable_managed "$_dw_fs_platform" || die "GATE-12 Flutter stable managed verification failed after installation"
}

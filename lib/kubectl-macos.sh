#!/bin/sh
# Native macOS kubectl stable artifact transaction.
# Caller supplies KUBECTL_NATIVE_MANIFEST or uses the repository manifest path.

kubectl_macos_die() {
  printf '%s\n' "[devkit-wulf][kubectl@stable] $*" >&2
  return 2
}

kubectl_macos_have() { command -v "$1" >/dev/null 2>&1; }

kubectl_macos_manifest() {
  [ -n "${KUBECTL_NATIVE_MANIFEST:-}" ] || return 1
  [ -f "$KUBECTL_NATIVE_MANIFEST" ] && [ ! -L "$KUBECTL_NATIVE_MANIFEST" ] || return 1
  printf '%s' "$KUBECTL_NATIVE_MANIFEST"
}

kubectl_macos_architecture() {
  case "$(uname -m 2>/dev/null || printf unknown)" in
    x86_64|amd64) printf amd64 ;;
    arm64|aarch64) printf arm64 ;;
    *) return 1 ;;
  esac
}

kubectl_macos_sha256() {
  if kubectl_macos_have shasum; then shasum -a 256 "$1" | awk '{print $1}'
  elif kubectl_macos_have sha256sum; then sha256sum "$1" | awk '{print $1}'
  else return 1
  fi
}

kubectl_macos_download() {
  _dw_km_url=$1
  _dw_km_destination=$2
  case "$_dw_km_url" in https://dl.k8s.io/release/*) ;; *) kubectl_macos_die "GATE-04 blocked untrusted kubectl URL: $_dw_km_url"; return 2 ;; esac
  kubectl_macos_have curl || { kubectl_macos_die 'curl is required for native macOS kubectl artifact downloads.'; return 2; }
  curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 --output "$_dw_km_destination" "$_dw_km_url"
}

kubectl_macos_paths() {
  _dw_km_manifest=$(kubectl_macos_manifest) || return 1
  [ -n "${HOME:-}" ] || return 1
  case "$HOME" in /*) ;; *) return 1 ;; esac
  _dw_km_template=$(jq -r '.targets.macos.root_template' "$_dw_km_manifest")
  [ "$_dw_km_template" = '{home}/.local/share/devkit-wulf/kubectl' ] || return 1
  _dw_km_root="$HOME/.local/share/devkit-wulf/kubectl"
  _dw_km_bin="$_dw_km_root/bin"
  _dw_km_binary="$_dw_km_bin/kubectl"
  _dw_km_marker="$_dw_km_root/.devkit-wulf-kubectl.json"
  printf '%s\n%s\n%s\n%s\n' "$_dw_km_root" "$_dw_km_bin" "$_dw_km_binary" "$_dw_km_marker"
}

kubectl_macos_resolve_version() {
  _dw_km_manifest=$(kubectl_macos_manifest) || return 1
  _dw_km_url=$(jq -r '.version.url' "$_dw_km_manifest")
  [ "$_dw_km_url" = 'https://dl.k8s.io/release/stable.txt' ] || return 1
  _dw_km_tmp=$(mktemp "${TMPDIR:-/tmp}/devkit-wulf-kubectl-version.XXXXXX") || return 1
  if ! kubectl_macos_download "$_dw_km_url" "$_dw_km_tmp"; then rm -f "$_dw_km_tmp"; return 1; fi
  _dw_km_version=$(tr -d '\r\n' < "$_dw_km_tmp")
  rm -f "$_dw_km_tmp"
  _dw_km_pattern=$(jq -r '.version.pattern' "$_dw_km_manifest")
  printf '%s\n' "$_dw_km_version" | grep -Eq "$_dw_km_pattern" || return 1
  printf '%s' "$_dw_km_version"
}

kubectl_macos_artifact() {
  _dw_km_manifest=$(kubectl_macos_manifest) || return 1
  _dw_km_arch=${1:-$(kubectl_macos_architecture)}
  jq -e --arg a "$_dw_km_arch" '.targets.macos.architectures[$a] == $a' "$_dw_km_manifest" >/dev/null || return 1
  _dw_km_version=$(kubectl_macos_resolve_version) || return 1
  _dw_km_url=$(jq -r --arg v "$_dw_km_version" --arg a "$_dw_km_arch" '.targets.macos.url_template | gsub("\\{version\\}";$v) | gsub("\\{architecture\\}";$a)' "$_dw_km_manifest")
  _dw_km_checksum=$(jq -r --arg v "$_dw_km_version" --arg a "$_dw_km_arch" '.targets.macos.checksum_url_template | gsub("\\{version\\}";$v) | gsub("\\{architecture\\}";$a)' "$_dw_km_manifest")
  case "$_dw_km_url" in "https://dl.k8s.io/release/$_dw_km_version/bin/darwin/$_dw_km_arch/kubectl") ;; *) return 1 ;; esac
  case "$_dw_km_checksum" in "https://dl.k8s.io/release/$_dw_km_version/bin/darwin/$_dw_km_arch/kubectl.sha256") ;; *) return 1 ;; esac
  printf '%s\n%s\n%s\n' "$_dw_km_version" "$_dw_km_url" "$_dw_km_checksum"
}

kubectl_macos_expected_sha256() {
  _dw_km_checksum_url=$1
  _dw_km_tmp=$(mktemp "${TMPDIR:-/tmp}/devkit-wulf-kubectl-sha.XXXXXX") || return 1
  if ! kubectl_macos_download "$_dw_km_checksum_url" "$_dw_km_tmp"; then rm -f "$_dw_km_tmp"; return 1; fi
  _dw_km_text=$(tr -d '\r\n' < "$_dw_km_tmp")
  rm -f "$_dw_km_tmp"
  _dw_km_sha=$(printf '%s\n' "$_dw_km_text" | awk '{print $1}' | tr 'A-F' 'a-f')
  printf '%s\n' "$_dw_km_sha" | grep -Eq '^[0-9a-f]{64}$' || return 1
  printf '%s' "$_dw_km_sha"
}

kubectl_macos_path_ready() {
  _dw_km_paths=$(kubectl_macos_paths) || return 1
  _dw_km_bin=$(printf '%s\n' "$_dw_km_paths" | sed -n '2p')
  _dw_km_old_ifs=$IFS
  IFS=:
  for _dw_km_entry in ${PATH:-}; do
    [ "$_dw_km_entry" = "$_dw_km_bin" ] && { IFS=$_dw_km_old_ifs; return 0; }
  done
  IFS=$_dw_km_old_ifs
  return 1
}

verify_kubectl_macos_managed() {
  _dw_km_manifest=$(kubectl_macos_manifest) || return 1
  _dw_km_arch=${1:-$(kubectl_macos_architecture)}
  _dw_km_paths=$(kubectl_macos_paths) || return 1
  _dw_km_root=$(printf '%s\n' "$_dw_km_paths" | sed -n '1p')
  _dw_km_bin=$(printf '%s\n' "$_dw_km_paths" | sed -n '2p')
  _dw_km_binary=$(printf '%s\n' "$_dw_km_paths" | sed -n '3p')
  _dw_km_marker=$(printf '%s\n' "$_dw_km_paths" | sed -n '4p')
  [ -d "$_dw_km_root" ] && [ ! -L "$_dw_km_root" ] || return 1
  [ -d "$_dw_km_bin" ] && [ ! -L "$_dw_km_bin" ] || return 1
  [ -f "$_dw_km_binary" ] && [ -x "$_dw_km_binary" ] && [ ! -L "$_dw_km_binary" ] || return 1
  [ -f "$_dw_km_marker" ] && [ ! -L "$_dw_km_marker" ] || return 1
  jq -e --arg a "$_dw_km_arch" '
    .environment == "kubectl" and .selector == "kubectl@stable" and .platform == "macos" and .architecture == $a
    and (.version | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
    and (.source_url | startswith("https://dl.k8s.io/release/") and contains("/bin/darwin/" + $a + "/kubectl"))
    and (.sha256 | test("^[0-9a-fA-F]{64}$"))
  ' "$_dw_km_marker" >/dev/null || return 1
  _dw_km_expected=$(jq -r '.sha256 | ascii_downcase' "$_dw_km_marker")
  _dw_km_actual=$(kubectl_macos_sha256 "$_dw_km_binary" | tr 'A-F' 'a-f') || return 1
  [ "$_dw_km_actual" = "$_dw_km_expected" ] || return 1
  _dw_km_version=$(jq -r '.version' "$_dw_km_marker")
  "$_dw_km_binary" version --client=true --output=json 2>/dev/null | jq -e --arg v "$_dw_km_version" '.clientVersion.gitVersion == $v' >/dev/null || return 1
  return 0
}

plan_kubectl_macos() {
  _dw_km_arch=${1:-$(kubectl_macos_architecture)}
  _dw_km_paths=$(kubectl_macos_paths) || return 1
  _dw_km_artifact=$(kubectl_macos_artifact "$_dw_km_arch") || return 1
  _dw_km_version=$(printf '%s\n' "$_dw_km_artifact" | sed -n '1p')
  _dw_km_url=$(printf '%s\n' "$_dw_km_artifact" | sed -n '2p')
  _dw_km_checksum=$(printf '%s\n' "$_dw_km_artifact" | sed -n '3p')
  _dw_km_sha=$(kubectl_macos_expected_sha256 "$_dw_km_checksum") || return 1
  printf '%s\n' "environment=kubectl" "selector=kubectl@stable" "platform=macos" "architecture=$_dw_km_arch" "version=$_dw_km_version" "source=$_dw_km_url" "checksum=$_dw_km_checksum" "sha256=$_dw_km_sha" "destination=$(printf '%s\n' "$_dw_km_paths" | sed -n '3p')" 'privileged=false' 'path_mutation=false' 'mutates_host=false'
}

install_kubectl_macos() {
  _dw_km_arch=${1:-$(kubectl_macos_architecture)}
  _dw_km_paths=$(kubectl_macos_paths) || { kubectl_macos_die 'unable to resolve native macOS kubectl paths'; return 2; }
  _dw_km_root=$(printf '%s\n' "$_dw_km_paths" | sed -n '1p')
  _dw_km_bin=$(printf '%s\n' "$_dw_km_paths" | sed -n '2p')
  _dw_km_binary=$(printf '%s\n' "$_dw_km_paths" | sed -n '3p')
  _dw_km_marker=$(printf '%s\n' "$_dw_km_paths" | sed -n '4p')

  if [ -e "$_dw_km_binary" ] || [ -L "$_dw_km_binary" ] || [ -e "$_dw_km_marker" ] || [ -L "$_dw_km_marker" ]; then
    verify_kubectl_macos_managed "$_dw_km_arch" && { printf '%s\n' 'result=already-satisfied'; return 0; }
    kubectl_macos_die 'GATE-08 existing kubectl selector destination is not an exact managed installation'; return 2
  fi
  kubectl_macos_path_ready || { kubectl_macos_die "GATE-13 PATH must already contain $_dw_km_bin; devkit-wulf will not modify PATH implicitly"; return 2; }

  _dw_km_artifact=$(kubectl_macos_artifact "$_dw_km_arch") || { kubectl_macos_die 'unable to resolve stable kubectl artifact'; return 2; }
  _dw_km_version=$(printf '%s\n' "$_dw_km_artifact" | sed -n '1p')
  _dw_km_url=$(printf '%s\n' "$_dw_km_artifact" | sed -n '2p')
  _dw_km_checksum=$(printf '%s\n' "$_dw_km_artifact" | sed -n '3p')
  _dw_km_expected=$(kubectl_macos_expected_sha256 "$_dw_km_checksum") || { kubectl_macos_die 'unable to resolve kubectl checksum'; return 2; }
  _dw_km_tmp=$(mktemp "${TMPDIR:-/tmp}/devkit-wulf-kubectl-bin.XXXXXX") || return 2
  if ! kubectl_macos_download "$_dw_km_url" "$_dw_km_tmp"; then rm -f "$_dw_km_tmp"; return 2; fi
  _dw_km_actual=$(kubectl_macos_sha256 "$_dw_km_tmp" | tr 'A-F' 'a-f') || { rm -f "$_dw_km_tmp"; return 2; }
  if [ "$_dw_km_actual" != "$_dw_km_expected" ]; then rm -f "$_dw_km_tmp"; kubectl_macos_die "GATE-05 kubectl SHA-256 mismatch: expected $_dw_km_expected, got $_dw_km_actual"; return 2; fi
  chmod 0755 "$_dw_km_tmp" || { rm -f "$_dw_km_tmp"; return 2; }

  mkdir -p "$_dw_km_bin" || { rm -f "$_dw_km_tmp"; return 2; }
  [ ! -L "$_dw_km_root" ] && [ ! -L "$_dw_km_bin" ] || { rm -f "$_dw_km_tmp"; kubectl_macos_die 'GATE-08 kubectl destination contains a symlink'; return 2; }
  mv "$_dw_km_tmp" "$_dw_km_binary" || return 2
  _dw_km_marker_tmp="$_dw_km_marker.tmp.$$"
  jq -n --arg a "$_dw_km_arch" --arg v "$_dw_km_version" --arg s "$_dw_km_url" --arg h "$_dw_km_expected" '{environment:"kubectl",selector:"kubectl@stable",platform:"macos",architecture:$a,publisher:"Kubernetes SIG CLI",version:$v,source_url:$s,sha256:$h,privileged:false,path_mutation:false}' > "$_dw_km_marker_tmp" || return 2
  mv "$_dw_km_marker_tmp" "$_dw_km_marker" || return 2
  verify_kubectl_macos_managed "$_dw_km_arch" || { kubectl_macos_die 'GATE-12 managed kubectl verification failed after installation'; return 2; }
  printf '%s\n' 'result=installed'
}

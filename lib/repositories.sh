#!/bin/sh
# Shared vendor-repository adapter for the POSIX orchestrator.
# Caller contract: jq, have, log, warn, die, privileged, install_packages,
# download_https, sha256_file, read_os_release_value, REPOSITORY_MANIFEST and STATE_DIR.

repository_definition_exists() {
  jq -e --arg e "$1" '.repositories[$e] != null' "$REPOSITORY_MANIFEST" >/dev/null 2>&1
}

repository_target_key() {
  _dw_repo_env=$1
  _dw_repo_platform=$2
  _dw_repo_family=$3
  if jq -e --arg e "$_dw_repo_env" --arg k "platform:$_dw_repo_platform" '.repositories[$e].targets[$k] != null' "$REPOSITORY_MANIFEST" >/dev/null 2>&1; then
    printf 'platform:%s' "$_dw_repo_platform"
    return 0
  fi
  if jq -e --arg e "$_dw_repo_env" --arg k "family:$_dw_repo_family" '.repositories[$e].targets[$k] != null' "$REPOSITORY_MANIFEST" >/dev/null 2>&1; then
    printf 'family:%s' "$_dw_repo_family"
    return 0
  fi
  return 1
}

repository_target_json() {
  _dw_repo_env=$1
  _dw_repo_platform=$2
  _dw_repo_family=$3
  _dw_repo_key=$(repository_target_key "$_dw_repo_env" "$_dw_repo_platform" "$_dw_repo_family") || return 0
  jq -c --arg e "$_dw_repo_env" --arg k "$_dw_repo_key" '.repositories[$e].targets[$k] // empty' "$REPOSITORY_MANIFEST"
}

native_package_json() {
  _dw_repo_env=$1
  _dw_repo_platform=$2
  jq -c --arg e "$_dw_repo_env" --arg p "$_dw_repo_platform" '.native_packages[$e][$p] // empty' "$REPOSITORY_MANIFEST"
}

repository_target_packages() {
  _dw_repo_target=$1
  printf '%s' "$_dw_repo_target" | jq -r 'if .package then .package else .packages[] end'
}

native_package_lines() {
  _dw_repo_env=$1
  _dw_repo_platform=$2
  _dw_repo_native=$(native_package_json "$_dw_repo_env" "$_dw_repo_platform")
  [ -n "$_dw_repo_native" ] || return 0
  printf '%s' "$_dw_repo_native" | jq -r 'if .package then .package else .packages[] end'
}

repository_target_compatible() {
  _dw_repo_target=$1
  _dw_repo_arch=$2
  _dw_repo_version=$3

  _dw_repo_arch_count=$(printf '%s' "$_dw_repo_target" | jq '.architectures // [] | length')
  if [ "$_dw_repo_arch_count" -gt 0 ]; then
    printf '%s' "$_dw_repo_target" | jq -e --arg a "$_dw_repo_arch" '(.architectures // []) | index($a) != null' >/dev/null || return 1
  fi

  _dw_repo_version_count=$(printf '%s' "$_dw_repo_target" | jq '.supported_versions // [] | length')
  if [ "$_dw_repo_version_count" -gt 0 ]; then
    [ -n "$_dw_repo_version" ] && [ "$_dw_repo_version" != unknown ] || return 1
    _dw_repo_version_ok=false
    while IFS= read -r _dw_repo_allowed; do
      [ -n "$_dw_repo_allowed" ] || continue
      case "$_dw_repo_version" in
        "$_dw_repo_allowed"|"$_dw_repo_allowed".*) _dw_repo_version_ok=true; break ;;
      esac
    done <<EOF
$(printf '%s' "$_dw_repo_target" | jq -r '.supported_versions[]?')
EOF
    [ "$_dw_repo_version_ok" = true ] || return 1
  fi
  return 0
}

repository_state_ready() {
  [ ! -L "$STATE_DIR" ] || die "GATE-10 refuses repository state-directory symlink: $STATE_DIR"
  mkdir -p "$STATE_DIR" || die "unable to create state directory: $STATE_DIR"
  [ -d "$STATE_DIR" ] && [ -w "$STATE_DIR" ] || die "state directory is not writable: $STATE_DIR"
  _dw_repo_state="$STATE_DIR/repositories.jsonl"
  [ ! -L "$_dw_repo_state" ] || die "GATE-10 refuses repository state symlink: $_dw_repo_state"
  if [ -e "$_dw_repo_state" ]; then
    [ -f "$_dw_repo_state" ] || die "GATE-10 repository state path is not a regular file: $_dw_repo_state"
    [ -w "$_dw_repo_state" ] || die "GATE-10 repository state file is not writable: $_dw_repo_state"
  fi
}

record_repository_state() {
  _dw_repo_env=$1
  _dw_repo_target=$2
  _dw_repo_action=$3
  _dw_repo_resource=$4
  _dw_repo_source=$5
  _dw_repo_sha=$6
  _dw_repo_created=$7
  repository_state_ready
  _dw_repo_timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  jq -nc \
    --arg timestamp "$_dw_repo_timestamp" \
    --arg environment "$_dw_repo_env" \
    --arg target "$_dw_repo_target" \
    --arg action "$_dw_repo_action" \
    --arg resource "$_dw_repo_resource" \
    --arg source "$_dw_repo_source" \
    --arg sha256 "$_dw_repo_sha" \
    --argjson created "$_dw_repo_created" \
    '{timestamp:$timestamp,environment:$environment,target:$target,action:$action,resource:$resource,source:$source,sha256:$sha256,created:$created}' \
    >> "$STATE_DIR/repositories.jsonl"
}

_repository_services_plan() {
  _dw_repo_entry=$1
  _dw_repo_services=$(printf '%s' "$_dw_repo_entry" | jq -r '.services[]? | .name + " [" + .action + "]"')
  if [ -n "$_dw_repo_services" ]; then
    printf '  services:\n'
    printf '%s\n' "$_dw_repo_services" | sed 's/^/    - /'
  fi
}

plan_native_package() {
  _dw_repo_env=$1
  _dw_repo_platform=$2
  _dw_repo_pm=$3
  _dw_repo_native=$(native_package_json "$_dw_repo_env" "$_dw_repo_platform")
  [ -n "$_dw_repo_native" ] || return 1
  _dw_repo_expected_pm=$(printf '%s' "$_dw_repo_native" | jq -r '.package_manager')
  [ "$_dw_repo_expected_pm" = "$_dw_repo_pm" ] || die "native package mapping requires $_dw_repo_expected_pm, detected $_dw_repo_pm"
  printf 'native_package:\n'
  printf '  documentation: %s\n' "$(printf '%s' "$_dw_repo_native" | jq -r '.documentation')"
  printf '  package_manager: %s\n' "$_dw_repo_expected_pm"
  printf '  packages:\n'
  native_package_lines "$_dw_repo_env" "$_dw_repo_platform" | sed 's/^/    - /'
  _repository_services_plan "$_dw_repo_native"
}

plan_vendor_repository() {
  _dw_repo_env=$1
  _dw_repo_platform=$2
  _dw_repo_family=$3
  _dw_repo_pm=$4
  _dw_repo_arch=$5
  _dw_repo_version=$6
  _dw_repo_target=$(repository_target_json "$_dw_repo_env" "$_dw_repo_platform" "$_dw_repo_family")
  [ -n "$_dw_repo_target" ] || return 1
  _dw_repo_target_key=$(repository_target_key "$_dw_repo_env" "$_dw_repo_platform" "$_dw_repo_family")
  _dw_repo_expected_pm=$(printf '%s' "$_dw_repo_target" | jq -r '.package_manager')
  [ "$_dw_repo_pm" = "$_dw_repo_expected_pm" ] || die "repository adapter requires $_dw_repo_expected_pm, detected $_dw_repo_pm"
  repository_target_compatible "$_dw_repo_target" "$_dw_repo_arch" "$_dw_repo_version" || die "GATE-02/03 repository adapter does not support $_dw_repo_platform/$_dw_repo_version/$_dw_repo_arch"
  _dw_repo_publisher=$(jq -r --arg e "$_dw_repo_env" '.repositories[$e].publisher' "$REPOSITORY_MANIFEST")

  printf 'vendor_repository:\n'
  printf '  target: %s\n' "$_dw_repo_target_key"
  printf '  publisher: %s\n' "$_dw_repo_publisher"
  printf '  documentation: %s\n' "$(printf '%s' "$_dw_repo_target" | jq -r '.documentation')"
  printf '  package_manager: %s\n' "$_dw_repo_expected_pm"
  printf '  packages:\n'; repository_target_packages "$_dw_repo_target" | sed 's/^/    - /'
  printf '  repository_file: %s\n' "$(printf '%s' "$_dw_repo_target" | jq -r '.repository_file')"
  _dw_repo_repository_url=$(printf '%s' "$_dw_repo_target" | jq -r '.repository_url // empty')
  [ -z "$_dw_repo_repository_url" ] || printf '  repository_url: %s\n' "$_dw_repo_repository_url"
  printf '  package_signature_required: %s\n' "$(printf '%s' "$_dw_repo_target" | jq -r '.package_signature_required')"
  printf '  repository_signature_required: %s\n' "$(printf '%s' "$_dw_repo_target" | jq -r '.repository_signature_required')"
  printf '  tls_verification_required: %s\n' "$(printf '%s' "$_dw_repo_target" | jq -r '.tls_verification_required')"
  printf '  privilege: required-for-package-repository-and-service-mutation\n'
  printf '  conflict_policy: preflight-refuse-installed-conflicts-or-different-content\n'
  printf '  prerequisites:\n'
  _dw_repo_prereqs=$(printf '%s' "$_dw_repo_target" | jq -r '.prerequisites[]?')
  if [ -n "$_dw_repo_prereqs" ]; then printf '%s\n' "$_dw_repo_prereqs" | sed 's/^/    - /'; else printf '    - none\n'; fi
  printf '  conflicting_packages:\n'
  _dw_repo_conflicts=$(printf '%s' "$_dw_repo_target" | jq -r '.conflicting_packages[]?')
  if [ -n "$_dw_repo_conflicts" ]; then printf '%s\n' "$_dw_repo_conflicts" | sed 's/^/    - /'; else printf '    - none\n'; fi
  printf '  keys:\n'
  printf '%s' "$_dw_repo_target" | jq -r '.keys[] | "    - " + .url + " [" + .transform + "]" + (if .fingerprint then " fingerprint=" + .fingerprint else "" end)'
  _repository_services_plan "$_dw_repo_target"
}

_repository_gpg_command() {
  if have gpg; then printf gpg; elif have gpg2; then printf gpg2; else return 1; fi
}

_repository_normalize_fingerprint() {
  printf '%s' "$1" | tr -d '[:space:]' | tr 'a-f' 'A-F'
}

_repository_stage_key() {
  _dw_repo_key=$1
  _dw_repo_tmpdir=$2
  _dw_repo_index=$3
  _dw_repo_url=$(printf '%s' "$_dw_repo_key" | jq -r '.url')
  _dw_repo_transform=$(printf '%s' "$_dw_repo_key" | jq -r '.transform')
  _dw_repo_expected_fingerprint=$(printf '%s' "$_dw_repo_key" | jq -r '.fingerprint // empty')
  _dw_repo_raw="$_dw_repo_tmpdir/key-$_dw_repo_index.raw"
  _dw_repo_staged="$_dw_repo_tmpdir/key-$_dw_repo_index.staged"
  download_https "$_dw_repo_url" "$_dw_repo_raw"
  [ -s "$_dw_repo_raw" ] || die "GATE-04 downloaded empty repository key: $_dw_repo_url"

  _dw_repo_gpg=$(_repository_gpg_command) || die "GATE-05 requires GnuPG to inspect repository key material before mutation"
  _dw_repo_actual_fingerprint=$("$_dw_repo_gpg" --no-tty --batch --with-colons --show-keys "$_dw_repo_raw" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  [ -n "$_dw_repo_actual_fingerprint" ] || die "GATE-05 rejected invalid OpenPGP key material from $_dw_repo_url"
  _dw_repo_actual_fingerprint=$(_repository_normalize_fingerprint "$_dw_repo_actual_fingerprint")
  if [ -n "$_dw_repo_expected_fingerprint" ]; then
    _dw_repo_expected_fingerprint=$(_repository_normalize_fingerprint "$_dw_repo_expected_fingerprint")
    [ "$_dw_repo_actual_fingerprint" = "$_dw_repo_expected_fingerprint" ] || die "GATE-05 repository key fingerprint mismatch for $_dw_repo_url"
  fi

  case "$_dw_repo_transform" in
    copy) cp "$_dw_repo_raw" "$_dw_repo_staged" ;;
    gpg-dearmor) "$_dw_repo_gpg" --no-tty --batch --dearmor --output "$_dw_repo_staged" "$_dw_repo_raw" || die "GATE-05 failed to dearmor repository key" ;;
    repository-key) cp "$_dw_repo_raw" "$_dw_repo_staged" ;;
    *) die "unsupported repository key transform: $_dw_repo_transform" ;;
  esac
  _dw_repo_hash=$(sha256_file "$_dw_repo_staged")
  [ "$_dw_repo_hash" != unavailable ] || die "GATE-05 requires local SHA-256 support"
  printf '%s|%s|%s|%s|%s\n' "$_dw_repo_url" "$_dw_repo_transform" "$_dw_repo_staged" "$_dw_repo_hash" "$_dw_repo_actual_fingerprint"
}

_repository_safe_token() {
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9._+-]+$'
}

_repository_resolve_suite() {
  _dw_repo_target=$1
  _dw_repo_resolver=$(printf '%s' "$_dw_repo_target" | jq -r '.suite_resolver // empty')
  case "$_dw_repo_resolver" in
    debian-codename)
      _dw_repo_value=$(read_os_release_value VERSION_CODENAME 2>/dev/null || true)
      ;;
    ubuntu-codename)
      _dw_repo_value=$(read_os_release_value UBUNTU_CODENAME 2>/dev/null || true)
      [ -n "$_dw_repo_value" ] || _dw_repo_value=$(read_os_release_value VERSION_CODENAME 2>/dev/null || true)
      ;;
    '') return 1 ;;
    *) die "unsupported repository suite resolver: $_dw_repo_resolver" ;;
  esac
  [ -n "$_dw_repo_value" ] && _repository_safe_token "$_dw_repo_value" || die "GATE-03 rejected repository suite value"
  printf '%s' "$_dw_repo_value"
}

_repository_resolve_architecture() {
  _dw_repo_target=$1
  _dw_repo_resolver=$(printf '%s' "$_dw_repo_target" | jq -r '.architecture_resolver // empty')
  case "$_dw_repo_resolver" in
    dpkg)
      have dpkg || die "repository architecture resolver requires dpkg"
      _dw_repo_value=$(dpkg --print-architecture)
      ;;
    '') return 1 ;;
    *) die "unsupported repository architecture resolver: $_dw_repo_resolver" ;;
  esac
  [ -n "$_dw_repo_value" ] && _repository_safe_token "$_dw_repo_value" || die "GATE-03 rejected repository architecture value"
  printf '%s' "$_dw_repo_value"
}

_repository_validate_config_security() {
  _dw_repo_file=$1
  if grep -Eiq '^[[:space:]]*gpgcheck[[:space:]]*=[[:space:]]*0([[:space:]]|$)' "$_dw_repo_file"; then
    die "GATE-05 repository configuration disables package signature verification"
  fi
  if grep -Eiq '^[[:space:]]*sslverify[[:space:]]*=[[:space:]]*0([[:space:]]|$)' "$_dw_repo_file"; then
    die "GATE-04 repository configuration disables TLS verification"
  fi
}

_repository_stage_configuration() {
  _dw_repo_target=$1
  _dw_repo_tmpdir=$2
  _dw_repo_dest="$_dw_repo_tmpdir/repository.conf"
  _dw_repo_url=$(printf '%s' "$_dw_repo_target" | jq -r '.repository_url // empty')
  _dw_repo_static=$(printf '%s' "$_dw_repo_target" | jq -r 'has("repository_content")')
  _dw_repo_template=$(printf '%s' "$_dw_repo_target" | jq -r 'has("repository_content_template")')

  if [ -n "$_dw_repo_url" ]; then
    download_https "$_dw_repo_url" "$_dw_repo_dest"
    [ -s "$_dw_repo_dest" ] || die "GATE-04 downloaded empty repository configuration: $_dw_repo_url"
    while IFS= read -r _dw_repo_required; do
      [ -n "$_dw_repo_required" ] || continue
      grep -Fq -- "$_dw_repo_required" "$_dw_repo_dest" || die "GATE-05 remote repository configuration missing required security marker: $_dw_repo_required"
    done <<EOF
$(printf '%s' "$_dw_repo_target" | jq -r '.repository_required_substrings[]?')
EOF
  elif [ "$_dw_repo_static" = true ]; then
    printf '%s' "$_dw_repo_target" | jq -j '.repository_content' > "$_dw_repo_dest"
  elif [ "$_dw_repo_template" = true ]; then
    _dw_repo_template_value=$(printf '%s' "$_dw_repo_target" | jq -r '.repository_content_template')
    _dw_repo_suite=$(_repository_resolve_suite "$_dw_repo_target" || true)
    _dw_repo_arch_value=$(_repository_resolve_architecture "$_dw_repo_target" || true)
    if printf '%s' "$_dw_repo_template_value" | grep -Fq '{suite}'; then [ -n "$_dw_repo_suite" ] || die "repository template requires suite resolver"; fi
    if printf '%s' "$_dw_repo_template_value" | grep -Fq '{architecture}'; then [ -n "$_dw_repo_arch_value" ] || die "repository template requires architecture resolver"; fi
    printf '%s' "$_dw_repo_template_value" | sed -e "s/{suite}/$_dw_repo_suite/g" -e "s/{architecture}/$_dw_repo_arch_value/g" > "$_dw_repo_dest"
  else
    die "repository target has no configuration source"
  fi
  _repository_validate_config_security "$_dw_repo_dest"
  printf '%s' "$_dw_repo_dest"
}

_repository_preflight_file() {
  _dw_repo_source=$1
  _dw_repo_destination=$2
  [ ! -L "$_dw_repo_destination" ] || die "GATE-08 refuses symlink destination: $_dw_repo_destination"
  if [ -e "$_dw_repo_destination" ]; then
    [ -f "$_dw_repo_destination" ] || die "GATE-08 destination is not a regular file: $_dw_repo_destination"
    _dw_repo_new_hash=$(sha256_file "$_dw_repo_source")
    _dw_repo_existing_hash=$(sha256_file "$_dw_repo_destination")
    [ "$_dw_repo_new_hash" != unavailable ] && [ "$_dw_repo_existing_hash" != unavailable ] || die "GATE-05 requires local SHA-256 support"
    [ "$_dw_repo_existing_hash" = "$_dw_repo_new_hash" ] || die "GATE-08 conflict: $_dw_repo_destination differs from researched repository content"
  fi
}

_repository_install_file() {
  _dw_repo_env=$1
  _dw_repo_target_name=$2
  _dw_repo_source=$3
  _dw_repo_destination=$4
  _dw_repo_source_url=$5
  _dw_repo_mode=$6
  _repository_preflight_file "$_dw_repo_source" "$_dw_repo_destination"
  _dw_repo_new_hash=$(sha256_file "$_dw_repo_source")
  [ "$_dw_repo_new_hash" != unavailable ] || die "GATE-05 requires local SHA-256 support"
  if [ -e "$_dw_repo_destination" ]; then
    record_repository_state "$_dw_repo_env" "$_dw_repo_target_name" observed-exact-resource "$_dw_repo_destination" "$_dw_repo_source_url" "$_dw_repo_new_hash" false
    return 0
  fi
  record_repository_state "$_dw_repo_env" "$_dw_repo_target_name" mutation-intent "$_dw_repo_destination" "$_dw_repo_source_url" "$_dw_repo_new_hash" true
  privileged install -m "$_dw_repo_mode" "$_dw_repo_source" "$_dw_repo_destination"
  _dw_repo_installed_hash=$(sha256_file "$_dw_repo_destination")
  [ "$_dw_repo_installed_hash" = "$_dw_repo_new_hash" ] || die "GATE-12 installed repository resource hash differs from staged resource"
  record_repository_state "$_dw_repo_env" "$_dw_repo_target_name" installed-resource "$_dw_repo_destination" "$_dw_repo_source_url" "$_dw_repo_new_hash" true
}

_repository_package_installed() {
  _dw_repo_pm=$1
  _dw_repo_package=$2
  case "$_dw_repo_pm" in
    apt)
      have dpkg-query || die "GATE-08 requires dpkg-query to inspect conflicting packages"
      dpkg-query -W -f='${Status}' "$_dw_repo_package" 2>/dev/null | grep -q '^install ok installed$'
      ;;
    dnf|zypper)
      have rpm || die "GATE-08 requires rpm to inspect conflicting packages"
      rpm -q "$_dw_repo_package" >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

_repository_preflight_package_conflicts() {
  _dw_repo_target=$1
  _dw_repo_pm=$2
  _dw_repo_found=
  while IFS= read -r _dw_repo_conflict; do
    [ -n "$_dw_repo_conflict" ] || continue
    if _repository_package_installed "$_dw_repo_pm" "$_dw_repo_conflict"; then
      if [ -n "$_dw_repo_found" ]; then _dw_repo_found="$_dw_repo_found, $_dw_repo_conflict"; else _dw_repo_found=$_dw_repo_conflict; fi
    fi
  done <<EOF
$(printf '%s' "$_dw_repo_target" | jq -r '.conflicting_packages[]?')
EOF
  [ -z "$_dw_repo_found" ] || die "GATE-08 conflicting packages detected: $_dw_repo_found; explicit migration/removal is required"
}

_repository_preflight_services() {
  _dw_repo_entry=$1
  _dw_repo_count=$(printf '%s' "$_dw_repo_entry" | jq '.services // [] | length')
  [ "$_dw_repo_count" -eq 0 ] && return 0
  have systemctl || die "service contract requires systemctl"
}

_repository_apply_services() {
  _dw_repo_env=$1
  _dw_repo_target_name=$2
  _dw_repo_entry=$3
  _repository_preflight_services "$_dw_repo_entry"
  while IFS= read -r _dw_repo_service; do
    [ -n "$_dw_repo_service" ] || continue
    _dw_repo_service_name=$(printf '%s' "$_dw_repo_service" | jq -r '.name')
    _dw_repo_service_action=$(printf '%s' "$_dw_repo_service" | jq -r '.action')
    record_repository_state "$_dw_repo_env" "$_dw_repo_target_name" service-intent "$_dw_repo_service_name" "$_dw_repo_service_action" "" false
    case "$_dw_repo_service_action" in
      start) privileged systemctl start "$_dw_repo_service_name" ;;
      enable-now) privileged systemctl enable --now "$_dw_repo_service_name" ;;
      *) die "unsupported service action: $_dw_repo_service_action" ;;
    esac
    record_repository_state "$_dw_repo_env" "$_dw_repo_target_name" service-applied "$_dw_repo_service_name" "$_dw_repo_service_action" "" false
  done <<EOF
$(printf '%s' "$_dw_repo_entry" | jq -c '.services[]?')
EOF
}

install_native_package() (
  set -eu
  _dw_repo_env=$1
  _dw_repo_platform=$2
  _dw_repo_pm=$3
  _dw_repo_native=$(native_package_json "$_dw_repo_env" "$_dw_repo_platform")
  [ -n "$_dw_repo_native" ] || die "no native package mapping for $_dw_repo_env/$_dw_repo_platform"
  _dw_repo_expected_pm=$(printf '%s' "$_dw_repo_native" | jq -r '.package_manager')
  [ "$_dw_repo_expected_pm" = "$_dw_repo_pm" ] || die "native package mapping requires $_dw_repo_expected_pm, detected $_dw_repo_pm"
  _repository_preflight_services "$_dw_repo_native"
  _dw_repo_packages=$(native_package_lines "$_dw_repo_env" "$_dw_repo_platform")
  [ -n "$_dw_repo_packages" ] || die "native package mapping contains no packages"
  # Package identifiers are schema-restricted tokens.
  # shellcheck disable=SC2086
  install_packages "$_dw_repo_pm" $_dw_repo_packages
  _repository_apply_services "$_dw_repo_env" "platform:$_dw_repo_platform" "$_dw_repo_native"
)

install_vendor_repository() (
  set -eu
  _dw_repo_env=$1
  _dw_repo_platform=$2
  _dw_repo_family=$3
  _dw_repo_pm=$4
  _dw_repo_arch=$5
  _dw_repo_version=$6
  _dw_repo_target=$(repository_target_json "$_dw_repo_env" "$_dw_repo_platform" "$_dw_repo_family")
  [ -n "$_dw_repo_target" ] || die "no vendor repository mapping for $_dw_repo_env/$_dw_repo_platform"
  _dw_repo_target_key=$(repository_target_key "$_dw_repo_env" "$_dw_repo_platform" "$_dw_repo_family")
  _dw_repo_expected_pm=$(printf '%s' "$_dw_repo_target" | jq -r '.package_manager')
  [ "$_dw_repo_pm" = "$_dw_repo_expected_pm" ] || die "repository adapter requires $_dw_repo_expected_pm, detected $_dw_repo_pm"
  repository_target_compatible "$_dw_repo_target" "$_dw_repo_arch" "$_dw_repo_version" || die "GATE-02/03 repository adapter does not support $_dw_repo_platform/$_dw_repo_version/$_dw_repo_arch"
  [ "$(printf '%s' "$_dw_repo_target" | jq -r '.tls_verification_required')" = true ] || die "GATE-04 refuses repository with TLS verification disabled"
  [ "$(printf '%s' "$_dw_repo_target" | jq -r '.package_signature_required')" = true ] || die "GATE-05 refuses repository without package signature verification"
  _repository_preflight_package_conflicts "$_dw_repo_target" "$_dw_repo_pm"
  _repository_preflight_services "$_dw_repo_target"

  _dw_repo_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-repository.XXXXXX") || die "unable to create repository staging directory"
  trap 'rm -rf "$_dw_repo_tmpdir"' EXIT HUP INT TERM

  _dw_repo_staged_keys="$_dw_repo_tmpdir/keys.tsv"
  : > "$_dw_repo_staged_keys"
  _dw_repo_key_index=0
  while IFS= read -r _dw_repo_key; do
    [ -n "$_dw_repo_key" ] || continue
    _dw_repo_key_index=$((_dw_repo_key_index + 1))
    _dw_repo_stage=$(_repository_stage_key "$_dw_repo_key" "$_dw_repo_tmpdir" "$_dw_repo_key_index")
    _dw_repo_key_url=$(printf '%s' "$_dw_repo_stage" | cut -d '|' -f 1)
    _dw_repo_key_transform=$(printf '%s' "$_dw_repo_stage" | cut -d '|' -f 2)
    _dw_repo_key_file=$(printf '%s' "$_dw_repo_stage" | cut -d '|' -f 3)
    _dw_repo_key_hash=$(printf '%s' "$_dw_repo_stage" | cut -d '|' -f 4)
    _dw_repo_key_fingerprint=$(printf '%s' "$_dw_repo_stage" | cut -d '|' -f 5)
    _dw_repo_key_destination=$(printf '%s' "$_dw_repo_key" | jq -r '.destination // empty')
    if [ -n "$_dw_repo_key_destination" ]; then
      _repository_preflight_file "$_dw_repo_key_file" "$_dw_repo_key_destination"
    elif [ "$_dw_repo_key_transform" != repository-key ]; then
      die "repository key without destination must use repository-key transform"
    fi
    printf '%s|%s|%s|%s|%s|%s\n' "$_dw_repo_key_url" "$_dw_repo_key_transform" "$_dw_repo_key_file" "$_dw_repo_key_hash" "$_dw_repo_key_fingerprint" "$_dw_repo_key_destination" >> "$_dw_repo_staged_keys"
  done <<EOF
$(printf '%s' "$_dw_repo_target" | jq -c '.keys[]')
EOF

  _dw_repo_key_dir=$(printf '%s' "$_dw_repo_target" | jq -r '.key_directory // empty')
  if [ -n "$_dw_repo_key_dir" ]; then
    [ ! -L "$_dw_repo_key_dir" ] || die "GATE-08 refuses symlink key directory: $_dw_repo_key_dir"
    if [ -e "$_dw_repo_key_dir" ]; then [ -d "$_dw_repo_key_dir" ] || die "GATE-08 key directory path is not a directory: $_dw_repo_key_dir"; fi
  fi

  _dw_repo_repo_file=$(printf '%s' "$_dw_repo_target" | jq -r '.repository_file')
  _dw_repo_parent=$(dirname "$_dw_repo_repo_file")
  [ -d "$_dw_repo_parent" ] || die "GATE-08 repository directory does not exist: $_dw_repo_parent"
  [ ! -L "$_dw_repo_parent" ] || die "GATE-08 refuses symlink repository directory: $_dw_repo_parent"
  _dw_repo_staged_repo=$(_repository_stage_configuration "$_dw_repo_target" "$_dw_repo_tmpdir")
  _repository_preflight_file "$_dw_repo_staged_repo" "$_dw_repo_repo_file"

  repository_state_ready

  _dw_repo_prereqs=$(printf '%s' "$_dw_repo_target" | jq -r '.prerequisites[]?')
  if [ -n "$_dw_repo_prereqs" ]; then
    record_repository_state "$_dw_repo_env" "$_dw_repo_target_key" prerequisite-intent package-manager "$_dw_repo_expected_pm" "" false
    # shellcheck disable=SC2086
    install_packages "$_dw_repo_expected_pm" $_dw_repo_prereqs
  fi

  if [ -n "$_dw_repo_key_dir" ] && [ ! -d "$_dw_repo_key_dir" ]; then
    record_repository_state "$_dw_repo_env" "$_dw_repo_target_key" mutation-intent "$_dw_repo_key_dir" directory "" true
    privileged install -d -m 0755 "$_dw_repo_key_dir"
    record_repository_state "$_dw_repo_env" "$_dw_repo_target_key" installed-directory "$_dw_repo_key_dir" directory "" true
  fi

  while IFS='|' read -r _dw_repo_key_url _dw_repo_key_transform _dw_repo_key_file _dw_repo_key_hash _dw_repo_key_fingerprint _dw_repo_key_destination; do
    [ -n "$_dw_repo_key_url" ] || continue
    log "GATE-04 repository key source: $_dw_repo_key_url"
    log "GATE-05 repository key parsed; fingerprint=$_dw_repo_key_fingerprint; observed SHA-256=$_dw_repo_key_hash"
    if [ -n "$_dw_repo_key_destination" ]; then
      _repository_install_file "$_dw_repo_env" "$_dw_repo_target_key" "$_dw_repo_key_file" "$_dw_repo_key_destination" "$_dw_repo_key_url" 0644
    else
      record_repository_state "$_dw_repo_env" "$_dw_repo_target_key" observed-repository-key repository-key "$_dw_repo_key_url" "$_dw_repo_key_hash" false
    fi
  done < "$_dw_repo_staged_keys"

  _dw_repo_repo_source=$(printf '%s' "$_dw_repo_target" | jq -r '.repository_url // .documentation')
  _repository_install_file "$_dw_repo_env" "$_dw_repo_target_key" "$_dw_repo_staged_repo" "$_dw_repo_repo_file" "$_dw_repo_repo_source" 0644

  case "$_dw_repo_expected_pm" in
    apt) privileged apt-get update ;;
    dnf) : ;;
    zypper)
      _dw_repo_refresh=$(printf '%s' "$_dw_repo_target" | jq -r '.refresh_repositories[]?')
      if [ -n "$_dw_repo_refresh" ]; then
        while IFS= read -r _dw_repo_id; do
          [ -n "$_dw_repo_id" ] || continue
          privileged zypper --gpg-auto-import-keys refresh "$_dw_repo_id"
        done <<EOF
$_dw_repo_refresh
EOF
      else
        privileged zypper --gpg-auto-import-keys refresh
      fi
      ;;
    *) die "unsupported vendor repository package manager: $_dw_repo_expected_pm" ;;
  esac

  _dw_repo_packages=$(repository_target_packages "$_dw_repo_target")
  record_repository_state "$_dw_repo_env" "$_dw_repo_target_key" package-install-intent packages "$_dw_repo_expected_pm" "" false
  # shellcheck disable=SC2086
  install_packages "$_dw_repo_expected_pm" $_dw_repo_packages
  record_repository_state "$_dw_repo_env" "$_dw_repo_target_key" package-installed packages "$_dw_repo_expected_pm" "" false
  _repository_apply_services "$_dw_repo_env" "$_dw_repo_target_key" "$_dw_repo_target"
)

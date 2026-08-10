#!/bin/sh
# Shared vendor-repository adapter for the POSIX orchestrator.
# Caller contract: jq, have, log, warn, die, privileged, install_packages,
# download_https, sha256_file, REPOSITORY_MANIFEST and STATE_DIR.

repository_definition_exists() {
  jq -e --arg e "$1" '.repositories[$e] != null' "$REPOSITORY_MANIFEST" >/dev/null 2>&1
}

repository_target_json() {
  _dw_repo_env=$1
  _dw_repo_family=$2
  jq -c --arg e "$_dw_repo_env" --arg f "$_dw_repo_family" '.repositories[$e].targets[$f] // empty' "$REPOSITORY_MANIFEST"
}

native_package_json() {
  _dw_repo_env=$1
  _dw_repo_platform=$2
  jq -c --arg e "$_dw_repo_env" --arg p "$_dw_repo_platform" '.native_packages[$e][$p] // empty' "$REPOSITORY_MANIFEST"
}

repository_state_ready() {
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

plan_vendor_repository() {
  _dw_repo_env=$1
  _dw_repo_family=$2
  _dw_repo_pm=$3
  _dw_repo_target=$(repository_target_json "$_dw_repo_env" "$_dw_repo_family")
  [ -n "$_dw_repo_target" ] || return 1
  _dw_repo_expected_pm=$(printf '%s' "$_dw_repo_target" | jq -r '.package_manager')
  [ "$_dw_repo_pm" = "$_dw_repo_expected_pm" ] || die "repository adapter requires $_dw_repo_expected_pm, detected $_dw_repo_pm"
  _dw_repo_publisher=$(jq -r --arg e "$_dw_repo_env" '.repositories[$e].publisher' "$REPOSITORY_MANIFEST")

  printf 'vendor_repository:\n'
  printf '  publisher: %s\n' "$_dw_repo_publisher"
  printf '  documentation: %s\n' "$(printf '%s' "$_dw_repo_target" | jq -r '.documentation')"
  printf '  package_manager: %s\n' "$_dw_repo_expected_pm"
  printf '  package: %s\n' "$(printf '%s' "$_dw_repo_target" | jq -r '.package')"
  printf '  repository_file: %s\n' "$(printf '%s' "$_dw_repo_target" | jq -r '.repository_file')"
  printf '  package_signature_required: %s\n' "$(printf '%s' "$_dw_repo_target" | jq -r '.package_signature_required')"
  printf '  repository_signature_required: %s\n' "$(printf '%s' "$_dw_repo_target" | jq -r '.repository_signature_required')"
  printf '  tls_verification_required: %s\n' "$(printf '%s' "$_dw_repo_target" | jq -r '.tls_verification_required')"
  printf '  privilege: required-for-package-and-repository-mutation\n'
  printf '  conflict_policy: refuse-existing-different-content\n'
  printf '  prerequisites:\n'
  printf '%s' "$_dw_repo_target" | jq -r '.prerequisites[]' | sed 's/^/    - /'
  printf '  keys:\n'
  printf '%s' "$_dw_repo_target" | jq -r '.keys[] | "    - " + .url + " [" + .transform + "]"'
}

_repository_stage_key() {
  _dw_repo_key=$1
  _dw_repo_tmpdir=$2
  _dw_repo_index=$3
  _dw_repo_url=$(printf '%s' "$_dw_repo_key" | jq -r '.url')
  _dw_repo_transform=$(printf '%s' "$_dw_repo_key" | jq -r '.transform')
  _dw_repo_raw="$_dw_repo_tmpdir/key-$_dw_repo_index.raw"
  _dw_repo_staged="$_dw_repo_tmpdir/key-$_dw_repo_index.staged"
  download_https "$_dw_repo_url" "$_dw_repo_raw"
  [ -s "$_dw_repo_raw" ] || die "GATE-04 downloaded empty repository key: $_dw_repo_url"
  case "$_dw_repo_transform" in
    copy)
      cp "$_dw_repo_raw" "$_dw_repo_staged"
      ;;
    gpg-dearmor)
      have gpg || die "GATE-05 requires gpg for repository key dearmor"
      gpg --no-tty --batch --dearmor --output "$_dw_repo_staged" "$_dw_repo_raw" || die "GATE-05 failed to dearmor repository key"
      ;;
    repository-key)
      cp "$_dw_repo_raw" "$_dw_repo_staged"
      ;;
    *)
      die "unsupported repository key transform: $_dw_repo_transform"
      ;;
  esac
  _dw_repo_hash=$(sha256_file "$_dw_repo_staged")
  [ "$_dw_repo_hash" != unavailable ] || die "GATE-05 requires local SHA-256 support"
  printf '%s|%s|%s|%s\n' "$_dw_repo_url" "$_dw_repo_transform" "$_dw_repo_staged" "$_dw_repo_hash"
}

_repository_install_file() {
  _dw_repo_env=$1
  _dw_repo_target_name=$2
  _dw_repo_source=$3
  _dw_repo_destination=$4
  _dw_repo_source_url=$5
  _dw_repo_mode=$6

  [ ! -L "$_dw_repo_destination" ] || die "GATE-08 refuses symlink destination: $_dw_repo_destination"
  _dw_repo_new_hash=$(sha256_file "$_dw_repo_source")
  [ "$_dw_repo_new_hash" != unavailable ] || die "GATE-05 requires local SHA-256 support"

  if [ -e "$_dw_repo_destination" ]; then
    [ -f "$_dw_repo_destination" ] || die "GATE-08 destination is not a regular file: $_dw_repo_destination"
    _dw_repo_existing_hash=$(sha256_file "$_dw_repo_destination")
    if [ "$_dw_repo_existing_hash" = "$_dw_repo_new_hash" ]; then
      record_repository_state "$_dw_repo_env" "$_dw_repo_target_name" observed-exact-resource "$_dw_repo_destination" "$_dw_repo_source_url" "$_dw_repo_new_hash" false
      return 0
    fi
    die "GATE-08 conflict: $_dw_repo_destination differs from researched repository content"
  fi

  record_repository_state "$_dw_repo_env" "$_dw_repo_target_name" mutation-intent "$_dw_repo_destination" "$_dw_repo_source_url" "$_dw_repo_new_hash" true
  privileged install -m "$_dw_repo_mode" "$_dw_repo_source" "$_dw_repo_destination"
  _dw_repo_installed_hash=$(sha256_file "$_dw_repo_destination")
  [ "$_dw_repo_installed_hash" = "$_dw_repo_new_hash" ] || die "GATE-12 installed repository resource hash differs from staged resource"
  record_repository_state "$_dw_repo_env" "$_dw_repo_target_name" installed-resource "$_dw_repo_destination" "$_dw_repo_source_url" "$_dw_repo_new_hash" true
}

install_vendor_repository() (
  set -eu
  _dw_repo_env=$1
  _dw_repo_family=$2
  _dw_repo_pm=$3
  _dw_repo_target=$(repository_target_json "$_dw_repo_env" "$_dw_repo_family")
  [ -n "$_dw_repo_target" ] || die "no vendor repository mapping for $_dw_repo_env/$_dw_repo_family"
  _dw_repo_expected_pm=$(printf '%s' "$_dw_repo_target" | jq -r '.package_manager')
  [ "$_dw_repo_pm" = "$_dw_repo_expected_pm" ] || die "repository adapter requires $_dw_repo_expected_pm, detected $_dw_repo_pm"
  [ "$(printf '%s' "$_dw_repo_target" | jq -r '.tls_verification_required')" = true ] || die "GATE-04 refuses repository with TLS verification disabled"
  [ "$(printf '%s' "$_dw_repo_target" | jq -r '.package_signature_required')" = true ] || die "GATE-05 refuses repository without package signature verification"

  repository_state_ready
  _dw_repo_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-repository.XXXXXX") || die "unable to create repository staging directory"
  trap 'rm -rf "$_dw_repo_tmpdir"' EXIT HUP INT TERM

  _dw_repo_prereqs=$(printf '%s' "$_dw_repo_target" | jq -r '.prerequisites[]?')
  if [ -n "$_dw_repo_prereqs" ]; then
    record_repository_state "$_dw_repo_env" "$_dw_repo_family" prerequisite-intent package-manager "$_dw_repo_expected_pm" "" false
    # Package identifiers are schema-restricted tokens.
    # shellcheck disable=SC2086
    install_packages "$_dw_repo_expected_pm" $_dw_repo_prereqs
  fi

  _dw_repo_key_dir=$(printf '%s' "$_dw_repo_target" | jq -r '.key_directory // empty')
  if [ -n "$_dw_repo_key_dir" ]; then
    [ ! -L "$_dw_repo_key_dir" ] || die "GATE-08 refuses symlink key directory: $_dw_repo_key_dir"
    if [ ! -d "$_dw_repo_key_dir" ]; then
      record_repository_state "$_dw_repo_env" "$_dw_repo_family" mutation-intent "$_dw_repo_key_dir" directory "" true
      privileged install -d -m 0755 "$_dw_repo_key_dir"
      record_repository_state "$_dw_repo_env" "$_dw_repo_family" installed-directory "$_dw_repo_key_dir" directory "" true
    fi
  fi

  _dw_repo_key_index=0
  printf '%s' "$_dw_repo_target" | jq -c '.keys[]' | while IFS= read -r _dw_repo_key; do
    _dw_repo_key_index=$((_dw_repo_key_index + 1))
    _dw_repo_stage=$(_repository_stage_key "$_dw_repo_key" "$_dw_repo_tmpdir" "$_dw_repo_key_index")
    _dw_repo_key_url=$(printf '%s' "$_dw_repo_stage" | cut -d '|' -f 1)
    _dw_repo_key_transform=$(printf '%s' "$_dw_repo_stage" | cut -d '|' -f 2)
    _dw_repo_key_file=$(printf '%s' "$_dw_repo_stage" | cut -d '|' -f 3)
    _dw_repo_key_hash=$(printf '%s' "$_dw_repo_stage" | cut -d '|' -f 4)
    log "GATE-04 repository key source: $_dw_repo_key_url"
    log "GATE-05 repository key SHA-256: $_dw_repo_key_hash"
    _dw_repo_key_destination=$(printf '%s' "$_dw_repo_key" | jq -r '.destination // empty')
    if [ -n "$_dw_repo_key_destination" ]; then
      _repository_install_file "$_dw_repo_env" "$_dw_repo_family" "$_dw_repo_key_file" "$_dw_repo_key_destination" "$_dw_repo_key_url" 0644
    elif [ "$_dw_repo_key_transform" != repository-key ]; then
      die "repository key without destination must use repository-key transform"
    fi
  done

  _dw_repo_repo_file=$(printf '%s' "$_dw_repo_target" | jq -r '.repository_file')
  _dw_repo_parent=$(dirname "$_dw_repo_repo_file")
  [ -d "$_dw_repo_parent" ] || die "GATE-08 repository directory does not exist: $_dw_repo_parent"
  [ ! -L "$_dw_repo_parent" ] || die "GATE-08 refuses symlink repository directory: $_dw_repo_parent"
  _dw_repo_staged_repo="$_dw_repo_tmpdir/repository.conf"
  printf '%s' "$_dw_repo_target" | jq -r '.repository_content' > "$_dw_repo_staged_repo"
  _repository_install_file "$_dw_repo_env" "$_dw_repo_family" "$_dw_repo_staged_repo" "$_dw_repo_repo_file" "$(printf '%s' "$_dw_repo_target" | jq -r '.documentation')" 0644

  case "$_dw_repo_expected_pm" in
    apt)
      privileged apt-get update
      ;;
    dnf)
      :
      ;;
    zypper)
      privileged zypper --gpg-auto-import-keys refresh opentofu
      privileged zypper --gpg-auto-import-keys refresh opentofu-source
      ;;
    *)
      die "unsupported vendor repository package manager: $_dw_repo_expected_pm"
      ;;
  esac

  _dw_repo_package=$(printf '%s' "$_dw_repo_target" | jq -r '.package')
  record_repository_state "$_dw_repo_env" "$_dw_repo_family" package-install-intent "$_dw_repo_package" "$_dw_repo_expected_pm" "" false
  install_packages "$_dw_repo_expected_pm" "$_dw_repo_package"
  record_repository_state "$_dw_repo_env" "$_dw_repo_family" package-installed "$_dw_repo_package" "$_dw_repo_expected_pm" "" false
)

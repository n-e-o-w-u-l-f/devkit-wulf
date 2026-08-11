#!/bin/sh
set -eu

fail() {
    printf '%s\n' "[devkit-wulf][python-3.12] $*" >&2
    exit 2
}

[ "$(uname -s 2>/dev/null || printf unknown)" = "Darwin" ] || fail "This adapter is for macOS only."
command -v brew >/dev/null 2>&1 || fail "Homebrew is required for the macOS Python 3.12 adapter."

ACTION=${1:-plan}
case "$ACTION" in
    plan|install|verify) ;;
    *) fail "Usage: $0 [plan|install|verify]" ;;
esac

FORMULA=python@3.12
MINIMUM_PATCH=3.12.13

version_ge() {
    awk -v have="$1" -v want="$2" 'BEGIN {
        split(have, h, "."); split(want, w, ".");
        for (i = 1; i <= 3; i++) {
            hv = h[i] + 0; wv = w[i] + 0;
            if (hv > wv) exit 0;
            if (hv < wv) exit 1;
        }
        exit 0;
    }'
}

python312_executable() {
    prefix=$(brew --prefix "$FORMULA" 2>/dev/null) || return 1
    candidate="$prefix/bin/python3.12"
    [ -x "$candidate" ] || return 1
    printf '%s\n' "$candidate"
}

cleanup_smoke_dir() {
    _dw_py_tmp=${1:-}
    [ -n "$_dw_py_tmp" ] || return 0
    case "$_dw_py_tmp" in
        "${TMPDIR:-/tmp}"/devkit-wulf-python312.*) rm -rf "$_dw_py_tmp" ;;
        *) fail "Refusing unsafe temporary cleanup path: $_dw_py_tmp" ;;
    esac
}

verify_python312() {
    exe=$(python312_executable) || fail "Homebrew-managed python@3.12 is not installed."
    version=$($exe -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])') || fail "Unable to query Python version."
    case "$version" in
        3.12.*) ;;
        *) fail "Homebrew runtime is not Python 3.12: $version" ;;
    esac
    version_ge "$version" "$MINIMUM_PATCH" || fail "Homebrew Python $version is below the researched security baseline $MINIMUM_PATCH. Run a Homebrew update/upgrade explicitly before retrying."

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/devkit-wulf-python312.XXXXXX") || fail "Unable to create venv smoke directory."
    trap 'cleanup_smoke_dir "$tmp"' EXIT HUP INT TERM
    "$exe" -m venv "$tmp" || fail "venv smoke test failed."
    "$tmp/bin/python" -m pip --version >/dev/null || fail "pip smoke test inside venv failed."
    cleanup_smoke_dir "$tmp"
    trap - EXIT HUP INT TERM
    tmp=''

    printf '%s\n' "python_executable=$exe"
    printf '%s\n' "python_version=$version"
}

case "$ACTION" in
    plan)
        printf '%s\n' 'environment=python'
        printf '%s\n' 'version_family=3.12'
        printf '%s\n' 'platform=macos'
        printf '%s\n' 'strategy=homebrew-formula'
        printf '%s\n' "formula=$FORMULA"
        printf '%s\n' "minimum_security_baseline=$MINIMUM_PATCH"
        printf '%s\n' 'system_python_replacement=false'
        printf '%s\n' 'brew_auto_update=false'
        HOMEBREW_NO_AUTO_UPDATE=1 brew info --json=v2 "$FORMULA" 2>/dev/null || fail "Unable to resolve Homebrew formula $FORMULA."
        ;;
    verify)
        verify_python312
        ;;
    install)
        if brew list --versions "$FORMULA" >/dev/null 2>&1; then
            verify_python312
            printf '%s\n' 'result=already-satisfied'
            exit 0
        fi
        HOMEBREW_NO_AUTO_UPDATE=1 brew install "$FORMULA"
        verify_python312
        printf '%s\n' 'result=installed'
        ;;
esac

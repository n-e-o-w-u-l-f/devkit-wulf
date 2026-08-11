#!/usr/bin/env python3
import json
import re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "manifests/go-artifact.json").read_text())
environments = json.loads((ROOT / "manifests/environments.json").read_text())
errors: list[str] = []

if manifest.get("schema_version") != 1: errors.append("Go artifact schema_version must be 1")
if manifest.get("research_date") != "2026-08-11": errors.append("Go artifact research_date drifted")
if manifest.get("publisher") != "The Go Authors": errors.append("Go publisher drifted")
if manifest.get("product") != "Go toolchain": errors.append("Go product drifted")
if manifest.get("support") != "experimental": errors.append("Go artifact support must remain experimental")

for label, expected in (("release_index_url", "https://go.dev/dl/?mode=json"), ("download_base", "https://go.dev/dl")):
    value = manifest.get(label, "")
    parsed = urlparse(value)
    if value != expected: errors.append(f"Go {label} drifted")
    if parsed.scheme != "https" or parsed.hostname != "go.dev": errors.append(f"Go {label} must remain on go.dev over HTTPS")

try:
    version_re = re.compile(manifest.get("version_pattern", ""))
except re.error as exc:
    errors.append(f"invalid Go version_pattern: {exc}")
else:
    if not version_re.fullmatch("go1.25.1") or version_re.fullmatch("../go1.25.1"):
        errors.append("Go version pattern does not enforce a safe stable token")

install = manifest.get("install", {})
expected_install = {
    "destination_template": "{home}/.local/share/devkit-wulf/go",
    "path_directory_template": "{home}/.local/share/devkit-wulf/go/bin",
    "marker_template": "{home}/.local/share/devkit-wulf/go/.devkit-wulf-go.json",
    "root_directory": "go",
    "critical_files": ["bin/go", "bin/gofmt"],
}
for key, expected in expected_install.items():
    if install.get(key) != expected: errors.append(f"Go install.{key} drifted")

expected_targets = {
    "linux": ("linux", ["amd64", "arm64", "riscv64", "ppc64le", "s390x"]),
    "macos": ("darwin", ["amd64", "arm64"]),
}
if set(manifest.get("targets", {})) != set(expected_targets): errors.append("Go artifact target OS set drifted")
for platform, (go_os, arches) in expected_targets.items():
    target = manifest.get("targets", {}).get(platform, {})
    if target.get("go_os") != go_os: errors.append(f"Go/{platform} upstream OS mapping drifted")
    if target.get("archive_format") != "tar.gz": errors.append(f"Go/{platform} archive format drifted")
    if target.get("architectures") != arches: errors.append(f"Go/{platform} architecture set drifted")

policy = manifest.get("policy", {})
for key in ("no_remote_script_execution", "no_path_mutation", "no_privilege"):
    if policy.get(key) is not True: errors.append(f"Go policy.{key} must remain true")
for key in ("safe_remove", "automatic_upgrade"):
    if policy.get(key) is not False: errors.append(f"Go policy.{key} must remain false")

# The artifact is an optional future effective strategy, not a support expansion.
go_env = environments.get("environments", {}).get("go", {})
if go_env.get("safe_remove") is not False: errors.append("Go environment safe_remove must remain false")
for platform in ("debian", "arch", "fedora", "rhel", "opensuse", "alpine", "macos"):
    entry = go_env.get("platforms", {}).get(platform)
    if not entry or entry.get("support") != "experimental" or entry.get("strategy") != "package-manager":
        errors.append(f"Go {platform} package-manager declaration changed unexpectedly")

if errors:
    for error in errors: print(f"ERROR: {error}")
    raise SystemExit(1)
print("Go verified artifact semantic validation passed")

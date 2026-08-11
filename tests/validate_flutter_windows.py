#!/usr/bin/env python3
import json
import re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "manifests/flutter-windows.json").read_text())
environments = json.loads((ROOT / "manifests/environments.json").read_text())

errors: list[str] = []

if manifest.get("schema_version") != 1:
    errors.append("Flutter Windows schema_version must be 1")
if manifest.get("research_date") != "2026-08-11":
    errors.append("Flutter Windows research_date drifted")
if manifest.get("publisher") != "Flutter Authors / Google":
    errors.append("Flutter Windows publisher drifted")
if manifest.get("product") != "Flutter SDK":
    errors.append("Flutter Windows product drifted")
if manifest.get("channel") != "stable":
    errors.append("Flutter Windows channel must remain stable")
if manifest.get("support") != "experimental":
    errors.append("Flutter Windows support must remain experimental")

for label, expected in (
    ("release_index_url", "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json"),
    ("expected_base_url", "https://storage.googleapis.com/flutter_infra_release/releases"),
):
    url = manifest.get(label, "")
    parsed = urlparse(url)
    if url != expected:
        errors.append(f"{label} drifted")
    if parsed.scheme != "https" or parsed.hostname != "storage.googleapis.com":
        errors.append(f"{label} must remain on Flutter's official storage host")

try:
    version_re = re.compile(manifest.get("version_pattern", ""))
except re.error as exc:
    errors.append(f"invalid version_pattern: {exc}")
else:
    if not version_re.fullmatch("3.35.0") or version_re.fullmatch("../3.35.0"):
        errors.append("version_pattern does not enforce safe Flutter versions")

target = manifest.get("target", {})
expected_target = {
    "architecture": "amd64",
    "release_architecture": "x64",
    "archive_format": "zip",
    "root_directory": "flutter",
    "destination_template": "{home}/develop/flutter",
    "path_directory_template": "{home}/develop/flutter/bin",
    "marker_relative_path": ".devkit-wulf-artifact.json",
}
for key, expected in expected_target.items():
    if target.get(key) != expected:
        errors.append(f"Flutter Windows target {key} drifted")
if target.get("critical_files") != ["bin/flutter.bat", "bin/dart.bat"]:
    errors.append("Flutter Windows critical-file set drifted")

try:
    archive_re = re.compile(target.get("archive_path_pattern", ""))
except re.error as exc:
    errors.append(f"invalid archive_path_pattern: {exc}")
else:
    if not archive_re.fullmatch("stable/windows/flutter_windows_3.35.0-stable.zip"):
        errors.append("archive_path_pattern rejects the expected official stable Windows shape")
    if archive_re.fullmatch("../stable/windows/flutter.zip"):
        errors.append("archive_path_pattern accepts traversal")

verification = manifest.get("verification", {})
if verification.get("managed_integrity") is not True:
    errors.append("managed integrity verification must remain required")
if verification.get("environment_commands") != ["flutter --version", "dart --version"]:
    errors.append("Flutter Windows environment verification commands drifted")

flutter_env = environments.get("environments", {}).get("flutter", {})
windows = flutter_env.get("platforms", {}).get("windows", {})
if windows.get("support") != "experimental":
    errors.append("Flutter Windows environment must remain experimental")
if windows.get("strategy") != "official-archive":
    errors.append("Flutter Windows environment must remain official-archive before effective CLI routing")
if windows.get("architectures") != ["amd64"]:
    errors.append("Flutter Windows environment architecture must exactly match the native adapter")
if flutter_env.get("safe_remove") is not False:
    errors.append("Flutter safe_remove must remain false until uninstall ownership is implemented")

if errors:
    for error in errors:
        print(f"ERROR: {error}")
    raise SystemExit(1)

print("Flutter Windows artifact semantic validation passed")

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

index = manifest.get("release_index_url", "")
base = manifest.get("expected_base_url", "")
for label, url in (("release_index_url", index), ("expected_base_url", base)):
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname != "storage.googleapis.com":
        errors.append(f"{label} must remain on Flutter's official storage host")
if index != "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json":
    errors.append("Flutter Windows release index URL drifted")
if base != "https://storage.googleapis.com/flutter_infra_release/releases":
    errors.append("Flutter release base URL drifted")

pattern = manifest.get("version_pattern", "")
try:
    compiled = re.compile(pattern)
except re.error as exc:
    errors.append(f"invalid version_pattern: {exc}")
else:
    if not compiled.fullmatch("3.35.0") or compiled.fullmatch("../3.35.0"):
        errors.append("version_pattern does not enforce safe semantic Flutter versions")

target = manifest.get("target", {})
if target.get("architecture") != "amd64":
    errors.append("Flutter Windows adapter must remain amd64-only")
if target.get("release_architecture") != "x64":
    errors.append("Flutter Windows release architecture must remain x64")
if target.get("archive_format") != "zip":
    errors.append("Flutter Windows archive format must remain zip")
if target.get("root_directory") != "flutter":
    errors.append("Flutter Windows archive root must remain flutter")
if target.get("destination_template") != "{home}/develop/flutter":
    errors.append("Flutter Windows destination template drifted")
if target.get("path_directory_template") != "{home}/develop/flutter/bin":
    errors.append("Flutter Windows PATH template drifted")
if target.get("marker_relative_path") != ".devkit-wulf-artifact.json":
    errors.append("Flutter Windows marker path drifted")
if target.get("critical_files") != ["bin/flutter.bat", "bin/dart.bat"]:
    errors.append("Flutter Windows critical-file set drifted")

archive_pattern = target.get("archive_path_pattern", "")
try:
    archive_re = re.compile(archive_pattern)
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

# Cross-check the already declared Windows environment boundary. This adapter is
# intentionally a realization of the existing experimental amd64 archive entry,
# not a support expansion.
flutter_env = environments.get("environments", {}).get("flutter", {})
windows = flutter_env.get("platforms", {}).get("windows", {})
if windows.get("support") != "experimental":
    errors.append("Flutter Windows environment must remain experimental")
if windows.get("strategy") != "official-archive":
    errors.append("Flutter Windows environment must remain official-archive before CLI effective routing")
if windows.get("architectures") != ["amd64"]:
    errors.append("Flutter Windows environment architecture must exactly match the native adapter")
if flutter_env.get("safe_remove") is not False:
    errors.append("Flutter safe_remove must remain false until uninstall ownership is implemented")

if errors:
    for error in errors:
        print(f"ERROR: {error}")
    raise SystemExit(1)

print("Flutter Windows artifact semantic validation passed")

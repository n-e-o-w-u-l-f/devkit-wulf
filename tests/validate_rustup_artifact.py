#!/usr/bin/env python3
import json
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "manifests/rustup-artifact.json").read_text())
environments = json.loads((ROOT / "manifests/environments.json").read_text())

errors: list[str] = []

if manifest.get("schema_version") != 1:
    errors.append("rustup artifact schema_version must be 1")
if manifest.get("research_date") != "2026-08-11":
    errors.append("rustup artifact research_date drifted")
if manifest.get("publisher") != "The Rust Project Developers":
    errors.append("rustup publisher drifted")
if manifest.get("product") != "rustup-init":
    errors.append("rustup product drifted")
if manifest.get("support") != "experimental":
    errors.append("rustup support must remain experimental")

source = manifest.get("source_base", "")
parsed = urlparse(source)
if source != "https://static.rust-lang.org/rustup/dist":
    errors.append("rustup source base drifted")
if parsed.scheme != "https" or parsed.hostname != "static.rust-lang.org":
    errors.append("rustup source must remain on static.rust-lang.org over HTTPS")
if manifest.get("checksum_suffix") != ".sha256":
    errors.append("rustup checksum suffix drifted")

install = manifest.get("install", {})
expected_install = {
    "profile": "minimal",
    "default_toolchain": "stable",
    "modify_path": False,
    "cargo_home_template": "{home}/.local/share/devkit-wulf/cargo",
    "rustup_home_template": "{home}/.local/share/devkit-wulf/rustup",
    "path_directory_template": "{home}/.local/share/devkit-wulf/cargo/bin",
    "marker_template": "{home}/.local/share/devkit-wulf/cargo/.devkit-wulf-rustup.json",
}
for key, expected in expected_install.items():
    if install.get(key) != expected:
        errors.append(f"rustup install.{key} drifted")

expected_targets = {
    "linux": {
        "amd64": "x86_64-unknown-linux-gnu",
        "arm64": "aarch64-unknown-linux-gnu",
    },
    "macos": {
        "amd64": "x86_64-apple-darwin",
        "arm64": "aarch64-apple-darwin",
    },
}
if set(manifest.get("targets", {})) != set(expected_targets):
    errors.append("rustup target OS set must remain Linux + macOS")
for platform, arches in expected_targets.items():
    target = manifest.get("targets", {}).get(platform, {})
    if target.get("binary_name") != "rustup-init":
        errors.append(f"rustup/{platform} binary name drifted")
    actual = {key: value.get("triple") for key, value in target.get("architectures", {}).items()}
    if actual != arches:
        errors.append(f"rustup/{platform} target triples drifted: {actual!r}")

verification = manifest.get("verification", {})
if verification.get("managed_binaries") != ["rustup", "rustc", "cargo"]:
    errors.append("rustup managed binary set drifted")
if verification.get("commands") != ["rustup --version", "rustc --version", "cargo --version"]:
    errors.append("rustup verification commands drifted")

policy = manifest.get("policy", {})
if policy.get("linux_libc") != "glibc":
    errors.append("rustup Linux artifact must remain glibc-scoped")
for key in ("no_remote_script_execution", "no_path_mutation", "no_privilege"):
    if policy.get(key) is not True:
        errors.append(f"rustup policy.{key} must remain true")
if policy.get("safe_remove") is not False:
    errors.append("rustup safe_remove must remain false")

# This contract replaces only the security mechanism behind the existing
# official-script Rust targets. It must not broaden the declarative environment.
rust = environments.get("environments", {}).get("rust", {})
if rust.get("safe_remove") is not False:
    errors.append("Rust environment safe_remove must remain false")
for platform in ("debian", "fedora", "rhel", "opensuse", "macos"):
    entry = rust.get("platforms", {}).get(platform)
    if not entry:
        errors.append(f"Rust environment missing existing {platform} entry")
        continue
    if entry.get("support") != "experimental" or entry.get("strategy") != "official-script":
        errors.append(f"Rust {platform} must remain experimental/official-script until central routing changes")
for platform in ("arch", "alpine", "freebsd", "openbsd"):
    entry = rust.get("platforms", {}).get(platform)
    if not entry or entry.get("strategy") != "package-manager":
        errors.append(f"Rust {platform} package-manager path must remain unchanged")

if errors:
    for error in errors:
        print(f"ERROR: {error}")
    raise SystemExit(1)

print("rustup verified artifact semantic validation passed")

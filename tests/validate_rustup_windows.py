#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests/rustup-windows.json"
SCHEMA = ROOT / "manifests/schema/rustup-windows.schema.json"
HELPER = ROOT / "lib/rustup-windows.ps1"
ADAPTER = ROOT / "installers/windows/environments/rust-stable.ps1"
FIXTURE = ROOT / "tests/test_rustup_windows.ps1"


def fail(message: str) -> None:
    raise AssertionError(message)


def load(path: Path) -> dict:
    if not path.is_file():
        fail(f"required file missing: {path.relative_to(ROOT)}")
    return json.loads(path.read_text(encoding="utf-8"))


def require_text(path: Path, *needles: str) -> str:
    if not path.is_file():
        fail(f"required file missing: {path.relative_to(ROOT)}")
    text = path.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            fail(f"{path.relative_to(ROOT)} missing invariant {needle!r}")
    return text


def main() -> int:
    manifest = load(MANIFEST)
    load(SCHEMA)

    if manifest.get("schema_version") != 1 or manifest.get("research_date") != "2026-08-11":
        fail("Windows rustup contract version/research date changed unexpectedly")
    if manifest.get("support") != "experimental" or manifest.get("publisher") != "The Rust Project":
        fail("Windows rustup publisher/support contract changed")
    if manifest.get("source") != "https://rust-lang.github.io/rustup/":
        fail("Windows rustup documentation source is not pinned")
    if manifest.get("distribution_base_url") != "https://static.rust-lang.org/rustup/dist":
        fail("Windows rustup distribution source is not pinned")

    target = manifest.get("target", {})
    if target.get("platform") != "windows":
        fail("native rustup contract must be Windows-only")
    if target.get("architectures") != {
        "amd64": "x86_64-pc-windows-msvc",
        "arm64": "aarch64-pc-windows-msvc",
    }:
        fail("Windows rustup target mapping changed unexpectedly")
    if target.get("filename") != "rustup-init.exe" or target.get("checksum_filename") != "rustup-init.exe.sha256":
        fail("Windows rustup artifact filenames changed")
    if target.get("root_template") != "{localappdata}/devkit-wulf":
        fail("Windows rustup root must remain user-local")
    if target.get("cargo_home_relative") != "cargo" or target.get("rustup_home_relative") != "rustup":
        fail("isolated CARGO_HOME/RUSTUP_HOME contract changed")
    if target.get("path_directory_relative") != "cargo/bin":
        fail("managed Cargo bin path changed")
    if target.get("critical_files") != [
        "cargo/bin/rustup.exe",
        "cargo/bin/rustc.exe",
        "cargo/bin/cargo.exe",
    ]:
        fail("critical Rust executable set changed")
    if target.get("integrity") != "sha256-sidecar" or target.get("privileged") is not False or target.get("path_mutation") is not False:
        fail("Windows rustup integrity/privilege/PATH contract changed")

    install = manifest.get("install", {})
    expected_args = ["-y", "--profile", "minimal", "--default-toolchain", "stable", "--no-modify-path"]
    if install.get("arguments") != expected_args or install.get("toolchain") != "stable" or install.get("profile") != "minimal" or install.get("modify_path") is not False:
        fail("Windows rustup installer arguments changed unexpectedly")

    helper = require_text(
        HELPER,
        "static.rust-lang.org",
        "/rustup/dist/",
        "rustup-init.exe.sha256",
        "Get-FileHash",
        "GATE-05 rustup-init.exe SHA-256 mismatch",
        "GATE-13 PATH must already contain",
        "CARGO_HOME",
        "RUSTUP_HOME",
        "Test-DevkitRustupWindowsManagedVerification",
        "rustup.exe",
        "rustc.exe",
        "cargo.exe",
        "show', 'active-toolchain",
        "automatic destructive rollback is intentionally refused",
    )
    forbidden_helper = (
        "sh.rustup.rs",
        "Invoke-Expression",
        "iex ",
        "SetEnvironmentVariable",
        "Start-Process",
        "sudo ",
        "doas ",
    )
    for needle in forbidden_helper:
        if needle.lower() in helper.lower():
            fail(f"Windows rustup helper contains forbidden behavior: {needle}")

    adapter = require_text(
        ADAPTER,
        "This adapter is for native Windows only",
        "install requires -Experimental",
        "manifests\\rustup-windows.json",
        "lib\\rustup-windows.ps1",
        "Get-DevkitRustupWindowsPlan",
        "Install-DevkitRustupWindowsArtifact",
        "Test-DevkitRustupWindowsManagedVerification",
    )
    if "sh.rustup.rs" in adapter or ".sh'" in adapter or '.sh"' in adapter:
        fail("native Windows Rust adapter must not invoke a POSIX rustup installer")

    fixture = require_text(
        FIXTURE,
        "Invoke-DevkitRustupWindowsDownload",
        "Invoke-DevkitRustupWindowsInstaller",
        "second installation must be fully offline",
        "tampered cargo.exe incorrectly verified",
        "foreign-home conflict must be detected before network",
        "checksum sidecar is malformed",
    )
    if "Invoke-WebRequest" in fixture:
        fail("offline Windows rustup fixture must not perform live network I/O")

    print("Windows rustup-init native contract: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, json.JSONDecodeError) as exc:
        print(f"Windows rustup-init native contract: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

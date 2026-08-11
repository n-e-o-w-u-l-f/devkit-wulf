#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests/kubectl-native.json"
SCHEMA = ROOT / "manifests/schema/kubectl-native.schema.json"
WINDOWS_HELPER = ROOT / "lib/kubectl-windows.ps1"
WINDOWS_ADAPTER = ROOT / "installers/windows/environments/kubectl-stable.ps1"
MACOS_HELPER = ROOT / "lib/kubectl-macos.sh"
MACOS_ADAPTER = ROOT / "installers/macos/environments/kubectl-stable.sh"


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
        fail("kubectl native contract version/research date changed unexpectedly")
    if manifest.get("support") != "experimental" or manifest.get("publisher") != "Kubernetes SIG CLI":
        fail("kubectl native support/publisher contract changed")
    version = manifest.get("version", {})
    if version != {
        "resolver": "text-url",
        "url": "https://dl.k8s.io/release/stable.txt",
        "pattern": "^v[0-9]+\\.[0-9]+\\.[0-9]+$",
    }:
        fail("kubectl stable resolver changed unexpectedly")

    targets = manifest.get("targets", {})
    if set(targets) != {"windows", "macos"}:
        fail("native kubectl contract must contain only Windows and macOS targets")

    windows = targets["windows"]
    if windows.get("architectures") != {"amd64": "amd64"}:
        fail("Windows kubectl is intentionally amd64-only until another native host architecture is reviewed")
    if windows.get("url_template") != "https://dl.k8s.io/release/{version}/bin/windows/{architecture}/kubectl.exe":
        fail("Windows kubectl URL template changed")
    if windows.get("checksum_url_template") != "https://dl.k8s.io/release/{version}/bin/windows/{architecture}/kubectl.exe.sha256":
        fail("Windows kubectl checksum template changed")
    if windows.get("root_template") != "{localappdata}/devkit-wulf/kubectl":
        fail("Windows kubectl root must remain user-local")

    macos = targets["macos"]
    if macos.get("architectures") != {"amd64": "amd64", "arm64": "arm64"}:
        fail("macOS kubectl architecture mapping changed")
    if macos.get("url_template") != "https://dl.k8s.io/release/{version}/bin/darwin/{architecture}/kubectl":
        fail("macOS kubectl URL template changed")
    if macos.get("checksum_url_template") != "https://dl.k8s.io/release/{version}/bin/darwin/{architecture}/kubectl.sha256":
        fail("macOS kubectl checksum template changed")
    if macos.get("root_template") != "{home}/.local/share/devkit-wulf/kubectl":
        fail("macOS kubectl root must remain user-local")

    for platform, target in targets.items():
        if target.get("integrity") != "sha256-sidecar" or target.get("privileged") is not False or target.get("path_mutation") is not False:
            fail(f"{platform}: integrity/privilege/PATH contract changed")
        if not str(target.get("source", "")).startswith("https://kubernetes.io/docs/tasks/tools/install-kubectl-"):
            fail(f"{platform}: official Kubernetes source documentation changed")

    windows_helper = require_text(
        WINDOWS_HELPER,
        "https://dl.k8s.io/release/stable.txt",
        "dl.k8s.io",
        "Get-FileHash",
        "kubectl.exe.sha256",
        "GATE-05 kubectl.exe SHA-256 mismatch",
        "GATE-13 PATH must already contain",
        "version --client=true --output=json",
        "clientVersion.gitVersion",
        "automatic destructive rollback is intentionally refused",
    )
    for forbidden in ("Invoke-Expression", "SetEnvironmentVariable", "Start-Process", "sudo ", "doas ", ".sh"):
        if forbidden.lower() in windows_helper.lower():
            fail(f"Windows kubectl helper contains forbidden cross-system/mutation behavior: {forbidden}")

    windows_adapter = require_text(
        WINDOWS_ADAPTER,
        "This adapter is for native Windows only",
        "install requires -Experimental",
        "manifests\\kubectl-native.json",
        "lib\\kubectl-windows.ps1",
        "Get-DevkitKubectlWindowsPlan",
        "Install-DevkitKubectlWindowsArtifact",
        "Test-DevkitKubectlWindowsManagedVerification",
    )
    if ".sh" in windows_adapter:
        fail("Windows kubectl adapter must not invoke a POSIX helper")

    macos_helper = require_text(
        MACOS_HELPER,
        "https://dl.k8s.io/release/stable.txt",
        "bin/darwin",
        "kubectl.sha256",
        "--proto '=https'",
        "GATE-05 kubectl SHA-256 mismatch",
        "GATE-13 PATH must already contain",
        "version --client=true --output=json",
        ".clientVersion.gitVersion == $v",
    )
    for forbidden in ("sudo ", "doas ", "powershell", "pwsh", "SetEnvironmentVariable"):
        if forbidden.lower() in macos_helper.lower():
            fail(f"macOS kubectl helper contains forbidden cross-system/mutation behavior: {forbidden}")

    require_text(
        MACOS_ADAPTER,
        "This adapter is for macOS only",
        "install requires --experimental",
        "manifests/kubectl-native.json",
        "lib/kubectl-macos.sh",
        "plan_kubectl_macos",
        "install_kubectl_macos",
        "verify_kubectl_macos_managed",
    )

    windows_fixture = require_text(
        ROOT / "tests/test_kubectl_windows.ps1",
        "second install must be fully offline",
        "tampered kubectl.exe incorrectly verified",
        "foreign conflict must be detected before network",
    )
    if "Invoke-WebRequest" in windows_fixture:
        fail("Windows kubectl offline fixture must not perform live network I/O")

    macos_fixture = require_text(
        ROOT / "tests/test_kubectl_macos.sh",
        "second install must be fully offline",
        "tampered kubectl incorrectly verified",
        "foreign conflict must be detected before network",
    )
    if "curl " in macos_fixture or "wget " in macos_fixture:
        fail("macOS kubectl offline fixture must not perform live network I/O")

    print("Native kubectl artifact contracts: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, json.JSONDecodeError) as exc:
        print(f"Native kubectl artifact contracts: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "environments/flutter/stable.json"
SCHEMA = ROOT / "environments/schema/flutter-stable.schema.json"
POSIX_ARTIFACTS = ROOT / "manifests/artifacts.json"
WINDOWS_ARTIFACT = ROOT / "manifests/flutter-windows.json"


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
    contract = load(CONTRACT)
    load(SCHEMA)
    posix_catalog = load(POSIX_ARTIFACTS)
    windows_manifest = load(WINDOWS_ARTIFACT)

    if contract.get("environment") != "flutter" or contract.get("selector") != "flutter@stable":
        fail("shared contract must describe flutter@stable")
    if contract.get("research_date") != "2026-08-11":
        fail("Flutter stable research date changed without contract refresh")
    if posix_catalog.get("research_date") != contract.get("research_date") or windows_manifest.get("research_date") != contract.get("research_date"):
        fail("Flutter shared contract and reviewed artifact contracts must share a research date")

    policy = contract.get("policy", {})
    expected_policy = {
        "support": "experimental",
        "no_path_mutation": True,
        "no_privilege": True,
        "automatic_upgrade": False,
        "wsl_inheritance": False,
    }
    if policy != expected_policy:
        fail("Flutter stable shared policy changed unexpectedly")

    adapters = contract.get("adapters", {})
    expected = {"windows-native", "linux-native", "macos-native", "wsl2-linux", "bsd-native", "solaris-illumos-native", "aix-native"}
    if set(adapters) != expected:
        fail(f"unexpected Flutter stable adapter set: {sorted(adapters)}")

    flutter_artifact = posix_catalog["artifacts"]["flutter"]
    linux_arch = list(flutter_artifact["targets"]["linux"]["architectures"].keys())
    mac_arch = list(flutter_artifact["targets"]["macos"]["architectures"].keys())
    if adapters["linux-native"].get("architectures") != linux_arch:
        fail("Linux Flutter architecture list must exactly match reviewed artifact catalog")
    if adapters["macos-native"].get("architectures") != mac_arch:
        fail("macOS Flutter architecture list must exactly match reviewed artifact catalog")
    if adapters["windows-native"].get("architectures") != [windows_manifest["target"]["architecture"]]:
        fail("Windows Flutter architecture list must exactly match reviewed native manifest")

    for adapter_id in ("linux-native", "macos-native"):
        adapter = adapters[adapter_id]
        if adapter.get("support") != "experimental" or adapter.get("strategy") != "verified-posix-artifact":
            fail(f"{adapter_id}: must remain experimental verified-posix-artifact")
        if adapter.get("artifact_manifest") != "manifests/artifacts.json" or adapter.get("artifact_id") != "flutter":
            fail(f"{adapter_id}: POSIX Flutter artifact contract changed unexpectedly")
        if adapter.get("helper") != "lib/artifacts.sh" or adapter.get("environment_helper") != "lib/flutter-posix-environment.sh":
            fail(f"{adapter_id}: reviewed shared helper paths changed unexpectedly")
        if not (ROOT / adapter["entrypoint"]).is_file():
            fail(f"{adapter_id}: system adapter missing")

    windows = adapters["windows-native"]
    if windows.get("support") != "experimental" or windows.get("strategy") != "verified-powershell-artifact":
        fail("Windows Flutter selector must remain experimental native PowerShell artifact")
    if windows.get("artifact_manifest") != "manifests/flutter-windows.json" or windows.get("helper") != "lib/flutter-windows.ps1":
        fail("Windows Flutter selector must use the reviewed Windows-specific contract")

    for adapter_id in ("wsl2-linux", "bsd-native", "solaris-illumos-native", "aix-native"):
        adapter = adapters[adapter_id]
        if adapter.get("support") != "unsupported" or adapter.get("strategy") != "unsupported":
            fail(f"{adapter_id}: must remain unsupported for flutter@stable")
        if len(adapter.get("reason", "")) < 20:
            fail(f"{adapter_id}: unsupported reason missing")

    helper = require_text(
        ROOT / "lib/flutter-posix-environment.sh",
        'critical_files:{"bin/flutter":$f,"bin/dart":$d}',
        'contains("/stable/" + $p + "/")',
        '[ -d "$_dw_fs_root/bin" ] && [ ! -L "$_dw_fs_root/bin" ]',
        'verify_flutter_stable_managed "$_dw_fs_platform"',
        'explicit migration/reinstall is required',
    )
    if "curl" in helper or "wget" in helper:
        fail("shared Flutter environment helper must not own network mechanics")

    linux = require_text(
        ROOT / adapters["linux-native"]["entrypoint"],
        "amd64 only",
        "lib/artifacts.sh",
        "lib/flutter-posix-environment.sh",
        "plan_verified_artifact flutter linux linux",
        "verify_flutter_stable_managed linux",
        "install_flutter_stable_managed linux linux",
        "install requires --experimental",
        "--proto '=https'",
    )
    if "sudo " in linux or "doas " in linux:
        fail("Linux Flutter selector must remain unprivileged")

    macos = require_text(
        ROOT / adapters["macos-native"]["entrypoint"],
        "Darwin",
        "lib/artifacts.sh",
        "lib/flutter-posix-environment.sh",
        "plan_verified_artifact flutter macos macos",
        "verify_flutter_stable_managed macos",
        "install_flutter_stable_managed macos macos",
        "install requires --experimental",
    )
    if "sudo " in macos:
        fail("macOS Flutter selector must remain unprivileged")

    windows_adapter = require_text(
        ROOT / windows["entrypoint"],
        "lib\\flutter-windows.ps1",
        "Get-DevkitFlutterWindowsPlan",
        "Install-DevkitFlutterWindowsArtifact",
        "Test-DevkitFlutterWindowsManagedVerification",
        "flutter.bat",
        "dart.bat",
        "install requires -Experimental",
    )
    if "artifacts.sh" in windows_adapter:
        fail("Windows Flutter adapter must not reuse the POSIX artifact installer")

    linux_wrapper = (ROOT / "installers/linux/devkit-wulf.sh").read_text(encoding="utf-8")
    mac_wrapper = (ROOT / "installers/macos/devkit-wulf.sh").read_text(encoding="utf-8")
    for family, text in (("linux", linux_wrapper), ("macos", mac_wrapper)):
        for needle in ('"${2:-}" = "flutter@stable"', "environments/flutter-stable.sh", "flutter@stable supports only plan, install and verify"):
            if needle not in text:
                fail(f"{family}: release entrypoint does not own flutter@stable route")
        if text.find('"${2:-}" = "flutter@stable"') > text.find('[ -f "$CORE" ]'):
            fail(f"{family}: Flutter route must precede generic core fallback")

    wsl_wrapper = (ROOT / "installers/wsl/devkit-wulf.sh").read_text(encoding="utf-8")
    if '"${2:-}" = "flutter@stable"' not in wsl_wrapper or "not enabled for WSL2" not in wsl_wrapper:
        fail("WSL release entrypoint must explicitly fail closed for flutter@stable")
    if "environments/flutter-stable.sh" in wsl_wrapper:
        fail("WSL must not inherit the native Linux Flutter selector adapter")

    windows_wrapper = (ROOT / "installers/windows/devkit-wulf.ps1").read_text(encoding="utf-8")
    for needle in ("$Target -eq 'flutter@stable'", "installers\\windows\\environments\\flutter-stable.ps1", "-Experimental:$Experimental"):
        if needle not in windows_wrapper:
            fail(f"Windows release entrypoint missing Flutter route invariant {needle!r}")
    if windows_wrapper.find("$Target -eq 'flutter@stable'") > windows_wrapper.find("Windows orchestrator core not found"):
        fail("Windows Flutter route must precede generic core fallback")

    if "flutter@stable" in (ROOT / "bin/devkit-wulf").read_text(encoding="utf-8"):
        fail("POSIX generic core must not absorb flutter@stable")
    if "flutter@stable" in (ROOT / "bin/devkit-wulf.ps1").read_text(encoding="utf-8"):
        fail("PowerShell generic core must not absorb flutter@stable")

    print("Flutter stable system-native contract: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, json.JSONDecodeError) as exc:
        print(f"Flutter stable system-native contract: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

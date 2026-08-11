#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "environments/go/stable.json"
SCHEMA = ROOT / "environments/schema/verified-artifact-environment.schema.json"
ARTIFACT = ROOT / "manifests/go-artifact.json"
WINDOWS_ARTIFACT = ROOT / "manifests/go-windows.json"
WINDOWS_SCHEMA = ROOT / "manifests/schema/go-windows.schema.json"


def fail(message: str) -> None:
    raise AssertionError(message)


def load(path: Path) -> dict:
    if not path.is_file():
        fail(f"required file missing: {path.relative_to(ROOT)}")
    return json.loads(path.read_text(encoding="utf-8"))


def require_text(path: Path, *needles: str) -> str:
    if not path.is_file():
        fail(f"required adapter missing: {path.relative_to(ROOT)}")
    text = path.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            fail(f"{path.relative_to(ROOT)} missing invariant {needle!r}")
    return text


def main() -> int:
    contract = load(CONTRACT)
    load(SCHEMA)
    artifact = load(ARTIFACT)
    windows_artifact = load(WINDOWS_ARTIFACT)
    load(WINDOWS_SCHEMA)

    if contract.get("environment") != "go" or contract.get("selector") != "go@stable":
        fail("shared contract must describe go@stable")
    if contract.get("artifact_manifest") != "manifests/go-artifact.json":
        fail("go@stable POSIX contract must keep the reviewed Go artifact manifest")
    if contract.get("research_date") != artifact.get("research_date") or contract.get("research_date") != windows_artifact.get("research_date"):
        fail("shared Go selector and reviewed POSIX/Windows contracts must share a research date")

    policy = contract.get("policy", {})
    if policy != {"support": "experimental", "no_path_mutation": True, "no_privilege": True, "automatic_upgrade": False}:
        fail("go@stable shared policy changed unexpectedly")

    verification = contract.get("verification", {})
    if not all(verification.get(key) is True for key in ("managed_artifact_required", "critical_hashes_required", "runtime_smoke_required")):
        fail("go@stable verification must remain marker/hash/runtime based")

    adapters = contract.get("adapters", {})
    posix_active = {
        "linux-native": ("linux", "installers/linux/environments/go-stable.sh"),
        "wsl2-linux": ("linux", "installers/wsl/environments/go-stable.sh"),
        "macos-native": ("macos", "installers/macos/environments/go-stable.sh"),
    }
    unsupported = {"bsd-native", "solaris-illumos-native", "aix-native"}
    expected = set(posix_active) | unsupported | {"windows-native"}
    if set(adapters) != expected:
        fail(f"unexpected go@stable adapter set: {sorted(adapters)}")

    for adapter_id, (artifact_platform, entrypoint) in posix_active.items():
        adapter = adapters[adapter_id]
        if adapter.get("support") != "experimental" or adapter.get("strategy") != "verified-artifact-helper":
            fail(f"{adapter_id}: must remain experimental verified-artifact-helper")
        if adapter.get("artifact_platform") != artifact_platform or adapter.get("helper") != "lib/go-artifact.sh" or adapter.get("entrypoint") != entrypoint:
            fail(f"{adapter_id}: reviewed POSIX adapter contract changed unexpectedly")
        expected_arch = artifact["targets"][artifact_platform]["architectures"]
        if adapter.get("architectures") != expected_arch:
            fail(f"{adapter_id}: architecture list must exactly match reviewed artifact target")

    windows = adapters["windows-native"]
    if windows.get("support") != "experimental" or windows.get("strategy") != "verified-powershell-artifact":
        fail("windows-native: Go stable must use the native verified PowerShell artifact strategy")
    if windows.get("artifact_platform") != "windows" or windows.get("artifact_manifest") != "manifests/go-windows.json":
        fail("windows-native: Go stable native artifact manifest mismatch")
    if windows.get("helper") != "lib/go-windows.ps1" or windows.get("entrypoint") != "installers/windows/environments/go-stable.ps1":
        fail("windows-native: Go stable native helper/entrypoint mismatch")
    if windows.get("architectures") != list(windows_artifact["target"]["architectures"].keys()):
        fail("windows-native: architectures must exactly match the native Windows manifest")

    for adapter_id in unsupported:
        adapter = adapters[adapter_id]
        if adapter.get("support") != "unsupported" or adapter.get("strategy") != "unsupported" or len(adapter.get("reason", "")) < 20:
            fail(f"{adapter_id}: must remain explicitly unsupported")

    linux = require_text(ROOT / adapters["linux-native"]["entrypoint"], "go-artifact.json", "lib/go-artifact.sh", "plan_go_artifact linux", "verify_go_artifact linux", "install_go_artifact linux", "install requires --experimental", "--proto '=https'")
    if "sudo " in linux or "doas " in linux or "curl |" in linux or "wget |" in linux:
        fail("Linux go@stable must remain unprivileged and stream-execution free")

    macos = require_text(ROOT / adapters["macos-native"]["entrypoint"], "Darwin", "go-artifact.json", "lib/go-artifact.sh", "plan_go_artifact macos", "verify_go_artifact macos", "install_go_artifact macos", "install requires --experimental")
    if "sudo " in macos:
        fail("macOS go@stable adapter must remain unprivileged")

    wsl = require_text(ROOT / adapters["wsl2-linux"]["entrypoint"], "microsoft|wsl", "../../linux/environments", "DEVKIT_WULF_ALLOW_WSL=1", "DEVKIT_WULF_REQUIRE_WSL=1")
    if "go-artifact.sh" in wsl or "download_https" in wsl:
        fail("WSL go@stable must reuse the Linux payload rather than duplicate artifact logic")

    windows_manifest_text = WINDOWS_ARTIFACT.read_text(encoding="utf-8")
    for needle in ('"release_index_url": "https://go.dev/dl/?mode=json"', '"download_base_url": "https://go.dev/dl"', '"archive_format": "zip"', '"amd64": "amd64"', '"arm64": "arm64"', '"privileged": false', '"path_mutation": false'):
        if needle not in windows_manifest_text:
            fail(f"native Windows Go manifest missing invariant {needle!r}")
    if ".msi" in windows_manifest_text:
        fail("user-local go@stable Windows selector must not use MSI")

    windows_helper = require_text(
        ROOT / "lib/go-windows.ps1",
        "https://go.dev/dl/?mode=json",
        "kind -eq 'archive'",
        '"$version.windows-$Architecture.zip"',
        "Get-FileHash",
        "Test-DevkitGoWindowsZipSafe",
        "GATE-05 Go archive SHA-256 mismatch",
        ".devkit-wulf-go-",
        "GATE-13 PATH must already contain",
        "Test-DevkitGoWindowsManagedVerification",
        "go.exe",
        "gofmt.exe",
    )
    if "Start-Process" in windows_helper and ".msi" in windows_helper:
        fail("Windows Go selector must not invoke an MSI installer")
    if "SetEnvironmentVariable" in windows_helper:
        fail("Windows Go selector must not mutate persistent PATH/environment variables")

    windows_adapter = require_text(ROOT / windows["entrypoint"], "lib\\go-windows.ps1", "Get-DevkitGoWindowsPlan", "Install-DevkitGoWindowsArtifact", "Test-DevkitGoWindowsManagedVerification", "install requires -Experimental")
    if "go-artifact.sh" in windows_adapter:
        fail("Windows Go adapter must not reuse the POSIX Go installer")

    for family in ("linux", "wsl", "macos"):
        wrapper = (ROOT / f"installers/{family}/devkit-wulf.sh").read_text(encoding="utf-8")
        for needle in ('"${2:-}" = "go@stable"', "environments/go-stable.sh", "go@stable supports only plan, install and verify"):
            if needle not in wrapper:
                fail(f"{family}: release entrypoint does not own go@stable route")
        if wrapper.find('"${2:-}" = "go@stable"') > wrapper.find('[ -f "$CORE" ]'):
            fail(f"{family}: go@stable must route before generic-core checks")

    windows_wrapper = (ROOT / "installers/windows/devkit-wulf.ps1").read_text(encoding="utf-8")
    for needle in ("$Target -eq 'go@stable'", "installers\\windows\\environments\\go-stable.ps1", "-Experimental:$Experimental"):
        if needle not in windows_wrapper:
            fail(f"Windows release entrypoint missing Go route invariant {needle!r}")
    if "go@stable is not enabled on Windows" in windows_wrapper:
        fail("obsolete Windows Go unsupported gate remains")
    if windows_wrapper.find("$Target -eq 'go@stable'") > windows_wrapper.find("Windows orchestrator core not found"):
        fail("Windows go@stable route must occur before generic-core fallback")

    if "go@stable" in (ROOT / "bin/devkit-wulf").read_text(encoding="utf-8") or "go@stable" in (ROOT / "bin/devkit-wulf.ps1").read_text(encoding="utf-8"):
        fail("generic cores must not absorb go@stable")

    print("Go stable system-native contract: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, json.JSONDecodeError) as exc:
        print(f"Go stable system-native contract: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

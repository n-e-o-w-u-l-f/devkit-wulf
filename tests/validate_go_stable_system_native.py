#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "environments/go/stable.json"
SCHEMA = ROOT / "environments/schema/verified-artifact-environment.schema.json"
ARTIFACT = ROOT / "manifests/go-artifact.json"


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

    if contract.get("environment") != "go" or contract.get("selector") != "go@stable":
        fail("shared contract must describe go@stable")
    if contract.get("artifact_manifest") != "manifests/go-artifact.json":
        fail("go@stable must use the verified Go artifact manifest")
    if contract.get("research_date") != artifact.get("research_date"):
        fail("shared Go selector research date must match artifact research date")

    policy = contract.get("policy", {})
    if policy != {
        "support": "experimental",
        "no_path_mutation": True,
        "no_privilege": True,
        "automatic_upgrade": False,
    }:
        fail("go@stable shared policy changed unexpectedly")

    verification = contract.get("verification", {})
    if not all(verification.get(key) is True for key in (
        "managed_artifact_required",
        "critical_hashes_required",
        "runtime_smoke_required",
    )):
        fail("go@stable verification must remain marker/hash/runtime based")

    adapters = contract.get("adapters", {})
    active = {
        "linux-native": ("linux", "installers/linux/environments/go-stable.sh"),
        "wsl2-linux": ("linux", "installers/wsl/environments/go-stable.sh"),
        "macos-native": ("macos", "installers/macos/environments/go-stable.sh"),
    }
    unsupported = {"windows-native", "bsd-native", "solaris-illumos-native", "aix-native"}
    if set(adapters) != set(active) | unsupported:
        fail(f"unexpected go@stable adapter set: {sorted(adapters)}")

    for adapter_id, (artifact_platform, entrypoint) in active.items():
        adapter = adapters[adapter_id]
        if adapter.get("support") != "experimental" or adapter.get("strategy") != "verified-artifact-helper":
            fail(f"{adapter_id}: must remain experimental verified-artifact-helper")
        if adapter.get("artifact_platform") != artifact_platform:
            fail(f"{adapter_id}: artifact platform mismatch")
        if adapter.get("helper") != "lib/go-artifact.sh":
            fail(f"{adapter_id}: verified helper changed unexpectedly")
        if adapter.get("entrypoint") != entrypoint:
            fail(f"{adapter_id}: entrypoint mismatch")
        expected_arch = artifact["targets"][artifact_platform]["architectures"]
        if adapter.get("architectures") != expected_arch:
            fail(f"{adapter_id}: architecture list must exactly match verified artifact target")

    for adapter_id in unsupported:
        adapter = adapters[adapter_id]
        if adapter.get("support") != "unsupported" or adapter.get("strategy") != "unsupported":
            fail(f"{adapter_id}: must remain unsupported for the current verified artifact contract")
        if len(adapter.get("reason", "")) < 20:
            fail(f"{adapter_id}: missing unsupported reason")

    linux = require_text(
        ROOT / adapters["linux-native"]["entrypoint"],
        "DEVKIT_WULF_ALLOW_WSL",
        "DEVKIT_WULF_REQUIRE_WSL",
        "go-artifact.json",
        "lib/go-artifact.sh",
        "plan_go_artifact linux",
        "verify_go_artifact linux",
        "install_go_artifact linux",
        "install requires --experimental",
        "--proto '=https'",
    )
    if "sudo " in linux or "doas " in linux:
        fail("Linux go@stable adapter must remain unprivileged")
    if "curl |" in linux or "wget |" in linux:
        fail("Linux go@stable adapter must not execute a download stream")

    macos = require_text(
        ROOT / adapters["macos-native"]["entrypoint"],
        "Darwin",
        "go-artifact.json",
        "lib/go-artifact.sh",
        "plan_go_artifact macos",
        "verify_go_artifact macos",
        "install_go_artifact macos",
        "install requires --experimental",
        "--proto '=https'",
    )
    if "sudo " in macos:
        fail("macOS go@stable adapter must remain unprivileged")

    wsl = require_text(
        ROOT / adapters["wsl2-linux"]["entrypoint"],
        "microsoft|wsl",
        "../../linux/environments",
        "DEVKIT_WULF_ALLOW_WSL=1",
        "DEVKIT_WULF_REQUIRE_WSL=1",
    )
    if "go-artifact.sh" in wsl or "download_https" in wsl:
        fail("WSL go@stable adapter must reuse the Linux payload rather than duplicate artifact logic")

    for family in ("linux", "wsl", "macos"):
        wrapper = (ROOT / f"installers/{family}/devkit-wulf.sh").read_text(encoding="utf-8")
        for needle in ('"${2:-}" = "go@stable"', "environments/go-stable.sh", "go@stable supports only plan, install and verify"):
            if needle not in wrapper:
                fail(f"{family}: release entrypoint does not own go@stable route")
        if wrapper.find('"${2:-}" = "go@stable"') > wrapper.find('[ -f "$CORE" ]'):
            fail(f"{family}: go@stable must route before generic-core checks")

    windows = (ROOT / "installers/windows/devkit-wulf.ps1").read_text(encoding="utf-8")
    if "$Target -eq 'go@stable'" not in windows or "not enabled on Windows" not in windows:
        fail("Windows release entrypoint must fail closed explicitly for go@stable")
    if windows.find("$Target -eq 'go@stable'") > windows.find("Windows orchestrator core not found"):
        fail("Windows go@stable failure must occur before generic-core fallback")

    if "go@stable" in (ROOT / "bin/devkit-wulf").read_text(encoding="utf-8"):
        fail("POSIX generic core must not absorb go@stable")
    if "go@stable" in (ROOT / "bin/devkit-wulf.ps1").read_text(encoding="utf-8"):
        fail("PowerShell generic core must not absorb go@stable")

    print("Go stable system-native contract: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, json.JSONDecodeError) as exc:
        print(f"Go stable system-native contract: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

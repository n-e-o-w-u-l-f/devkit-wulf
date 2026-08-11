#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "environments/rust/stable.json"
SCHEMA = ROOT / "environments/schema/verified-artifact-environment.schema.json"
ARTIFACT = ROOT / "manifests/rustup-artifact.json"


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
    artifact = load(ARTIFACT)

    if contract.get("environment") != "rust" or contract.get("selector") != "rust@stable":
        fail("shared contract must describe rust@stable")
    if contract.get("artifact_manifest") != "manifests/rustup-artifact.json":
        fail("rust@stable must reference the reviewed rustup artifact manifest")
    if contract.get("research_date") != artifact.get("research_date"):
        fail("rust@stable research date must match the reviewed artifact contract")

    if contract.get("policy") != {
        "support": "experimental",
        "no_path_mutation": True,
        "no_privilege": True,
        "automatic_upgrade": False,
    }:
        fail("rust@stable shared policy changed unexpectedly")

    verification = contract.get("verification", {})
    for key in ("managed_artifact_required", "critical_hashes_required", "runtime_smoke_required"):
        if verification.get(key) is not True:
            fail(f"rust@stable verification invariant disabled: {key}")

    adapters = contract.get("adapters", {})
    active = {
        "linux-native": ("linux", "installers/linux/environments/rust-stable.sh"),
        "wsl2-linux": ("linux", "installers/wsl/environments/rust-stable.sh"),
        "macos-native": ("macos", "installers/macos/environments/rust-stable.sh"),
    }
    unsupported = {"windows-native", "bsd-native", "solaris-illumos-native", "aix-native"}
    if set(adapters) != set(active) | unsupported:
        fail(f"unexpected rust@stable adapter set: {sorted(adapters)}")

    for adapter_id, (platform, entrypoint) in active.items():
        adapter = adapters[adapter_id]
        if adapter.get("support") != "experimental" or adapter.get("strategy") != "verified-artifact-helper":
            fail(f"{adapter_id}: must remain experimental verified-artifact-helper")
        if adapter.get("artifact_platform") != platform:
            fail(f"{adapter_id}: artifact platform mismatch")
        if adapter.get("helper") != "lib/rustup-artifact.sh":
            fail(f"{adapter_id}: helper changed unexpectedly")
        if adapter.get("entrypoint") != entrypoint:
            fail(f"{adapter_id}: entrypoint mismatch")
        expected_arch = list(artifact["targets"][platform]["architectures"].keys())
        if adapter.get("architectures") != expected_arch:
            fail(f"{adapter_id}: architecture list must exactly match reviewed rustup target")

    for adapter_id in unsupported:
        adapter = adapters[adapter_id]
        if adapter.get("support") != "unsupported" or adapter.get("strategy") != "unsupported":
            fail(f"{adapter_id}: must remain unsupported for this reviewed contract")
        if len(adapter.get("reason", "")) < 20:
            fail(f"{adapter_id}: unsupported reason missing")

    if artifact.get("policy", {}).get("linux_libc") != "glibc":
        fail("reviewed Rust Linux artifact contract must remain glibc-only")
    if artifact.get("policy", {}).get("no_remote_script_execution") is not True:
        fail("reviewed Rust artifact must continue to forbid remote-script execution")
    if artifact.get("install", {}).get("modify_path") is not False:
        fail("reviewed Rust artifact must continue to disable PATH mutation")

    linux = require_text(
        ROOT / adapters["linux-native"]["entrypoint"],
        "getconf GNU_LIBC_VERSION",
        "glibc-only",
        "rustup-artifact.json",
        "lib/rustup-artifact.sh",
        "plan_rustup_artifact linux",
        "verify_rustup_artifact linux",
        "install_rustup_artifact linux",
        "install requires --experimental",
        "--proto '=https'",
    )
    if "sudo " in linux or "doas " in linux:
        fail("Linux rust@stable adapter must remain unprivileged")
    if "sh.rustup.rs" in linux or "curl |" in linux or "wget |" in linux:
        fail("Linux rust@stable must execute only the verified rustup-init binary")

    macos = require_text(
        ROOT / adapters["macos-native"]["entrypoint"],
        "Darwin",
        "rustup-artifact.json",
        "lib/rustup-artifact.sh",
        "plan_rustup_artifact macos",
        "verify_rustup_artifact macos",
        "install_rustup_artifact macos",
        "install requires --experimental",
        "--proto '=https'",
    )
    if "sudo " in macos or "sh.rustup.rs" in macos:
        fail("macOS rust@stable adapter must remain unprivileged and script-free")

    wsl = require_text(
        ROOT / adapters["wsl2-linux"]["entrypoint"],
        "microsoft|wsl",
        "../../linux/environments",
        "DEVKIT_WULF_ALLOW_WSL=1",
        "DEVKIT_WULF_REQUIRE_WSL=1",
    )
    if "rustup-artifact.sh" in wsl or "download_https" in wsl:
        fail("WSL Rust adapter must reuse the Linux payload rather than duplicate artifact logic")

    for family in ("linux", "wsl", "macos"):
        wrapper = (ROOT / f"installers/{family}/devkit-wulf.sh").read_text(encoding="utf-8")
        for needle in ('"${2:-}" = "rust@stable"', "environments/rust-stable.sh", "rust@stable supports only plan, install and verify"):
            if needle not in wrapper:
                fail(f"{family}: release entrypoint does not own rust@stable route")
        if wrapper.find('"${2:-}" = "rust@stable"') > wrapper.find('[ -f "$CORE" ]'):
            fail(f"{family}: rust@stable must route before generic-core checks")

    windows = (ROOT / "installers/windows/devkit-wulf.ps1").read_text(encoding="utf-8")
    if "$Target -eq 'rust@stable'" not in windows or "not enabled on Windows" not in windows:
        fail("Windows must fail closed explicitly for rust@stable")
    if windows.find("$Target -eq 'rust@stable'") > windows.find("Windows orchestrator core not found"):
        fail("Windows rust@stable failure must occur before generic-core fallback")

    if "rust@stable" in (ROOT / "bin/devkit-wulf").read_text(encoding="utf-8"):
        fail("POSIX generic core must not absorb rust@stable")
    if "rust@stable" in (ROOT / "bin/devkit-wulf.ps1").read_text(encoding="utf-8"):
        fail("PowerShell generic core must not absorb rust@stable")

    print("Rust stable system-native contract: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, json.JSONDecodeError) as exc:
        print(f"Rust stable system-native contract: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests" / "installer-families.json"
SCHEMA = ROOT / "manifests" / "schema" / "installer-families.schema.json"

EXPECTED_FAMILIES = {
    "windows-native",
    "linux-native",
    "wsl2-linux",
    "macos-native",
    "bsd-native",
    "solaris-illumos-native",
    "aix-native",
}


def fail(message: str) -> None:
    raise AssertionError(message)


def load_json(path: Path) -> dict:
    if not path.is_file():
        fail(f"required JSON file missing: {path.relative_to(ROOT)}")
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def main() -> int:
    manifest = load_json(MANIFEST)
    load_json(SCHEMA)

    if manifest.get("schema_version") != 1:
        fail("installer family schema_version must be 1")
    if manifest.get("architecture") != "system-native-entrypoints-shared-environment-contracts":
        fail("unexpected installer architecture identifier")

    policy = manifest.get("policy", {})
    if policy.get("universal_release_artifact") is not False:
        fail("universal release artifacts must remain disabled")
    for key in (
        "shared_environment_contracts",
        "shared_internal_core_allowed",
        "system_native_entrypoint_required",
        "windows_executable_formats_windows_only",
        "wsl_runs_linux_payload_inside_distribution",
    ):
        if policy.get(key) is not True:
            fail(f"required installer policy is not enabled: {key}")

    shared = manifest.get("shared_contracts", {})
    if shared.get("environment_catalog") != "manifests/environments.json":
        fail("shared environment catalog path changed unexpectedly")
    if shared.get("version_specific_contract_root") != "environments":
        fail("version-specific shared contract root must be environments/")
    if not (ROOT / "environments").is_dir():
        fail("shared environments/ contract root is missing")

    families = manifest.get("families", {})
    if set(families) != EXPECTED_FAMILIES:
        fail(f"installer family set mismatch: {sorted(families)}")

    seen_entrypoints: set[str] = set()
    for family_id, family in families.items():
        entrypoint = family.get("entrypoint")
        core = family.get("internal_core")
        runtime = family.get("runtime")
        release_formats = set(family.get("release_formats", []))
        forbidden_formats = set(family.get("forbidden_release_formats", []))

        if not isinstance(entrypoint, str) or not entrypoint.startswith("installers/"):
            fail(f"{family_id}: invalid system-native entrypoint")
        if entrypoint in seen_entrypoints:
            fail(f"{family_id}: entrypoint is shared with another installer family")
        seen_entrypoints.add(entrypoint)

        entrypoint_path = ROOT / entrypoint
        if not entrypoint_path.is_file():
            fail(f"{family_id}: entrypoint does not exist: {entrypoint}")
        if not isinstance(core, str) or not (ROOT / core).is_file():
            fail(f"{family_id}: internal core does not exist: {core}")
        if release_formats & forbidden_formats:
            fail(f"{family_id}: release format is simultaneously allowed and forbidden")
        if "universal" in release_formats:
            fail(f"{family_id}: universal release format is forbidden")

        text = entrypoint_path.read_text(encoding="utf-8")
        if runtime == "powershell":
            if entrypoint_path.suffix.lower() != ".ps1":
                fail(f"{family_id}: PowerShell entrypoint must be .ps1")
            param_index = text.find("param(")
            strict_index = text.find("Set-StrictMode")
            if param_index < 0 or strict_index < 0 or param_index > strict_index:
                fail(f"{family_id}: PowerShell param block must precede executable statements")
            if "Windows_NT" not in text:
                fail(f"{family_id}: Windows host guard missing")
        elif runtime == "posix-sh":
            if entrypoint_path.suffix != ".sh":
                fail(f"{family_id}: POSIX entrypoint must be .sh")
            if not text.startswith("#!/bin/sh\n"):
                fail(f"{family_id}: POSIX entrypoint must use /bin/sh shebang")
            if "uname -s" not in text:
                fail(f"{family_id}: POSIX host-family guard missing")
        else:
            fail(f"{family_id}: unsupported runtime {runtime!r}")

        if family_id != "windows-native" and ({"exe", "msi"} & release_formats):
            fail(f"{family_id}: Windows executable formats leaked into non-Windows releases")

    windows = families["windows-native"]
    if windows.get("host_family") != "windows" or windows.get("domain") != "native":
        fail("windows-native family identity is invalid")
    if not {"ps1", "exe", "msi"}.issubset(set(windows["release_formats"])):
        fail("windows-native release formats must explicitly permit native Windows packaging")

    linux = families["linux-native"]
    if linux.get("host_family") != "linux" or linux.get("domain") != "native":
        fail("linux-native family identity is invalid")
    if "WSL detected" not in (ROOT / linux["entrypoint"]).read_text(encoding="utf-8"):
        fail("linux-native entrypoint must reject WSL")

    wsl = families["wsl2-linux"]
    if wsl.get("host_family") != "linux" or wsl.get("domain") != "wsl2":
        fail("wsl2-linux must be modeled as Linux in a distinct WSL2 domain")
    if wsl["entrypoint"] == linux["entrypoint"]:
        fail("WSL2 and native Linux require distinct release-facing entrypoints")
    wsl_text = (ROOT / wsl["entrypoint"]).read_text(encoding="utf-8").lower()
    if "microsoft" not in wsl_text or "wsl" not in wsl_text:
        fail("WSL2 entrypoint must explicitly prove WSL markers")

    print("installer family contract: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, json.JSONDecodeError) as exc:
        print(f"installer family contract: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

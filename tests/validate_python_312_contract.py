#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "environments" / "python" / "3.12.json"
SCHEMA = ROOT / "environments" / "schema" / "python-version.schema.json"

EXPECTED_ACTIVE = {
    "windows-native": ("python-install-manager", "installers/windows/environments/python-3.12.ps1"),
    "linux-native-ubuntu-24.04": ("apt", "installers/linux/environments/python-3.12.sh"),
    "wsl2-ubuntu-24.04": ("apt", "installers/wsl/environments/python-3.12.sh"),
    "macos-native": ("homebrew-formula", "installers/macos/environments/python-3.12.sh"),
}
EXPECTED_UNSUPPORTED = {"debian-12", "debian-13"}
ALLOWED_SOURCE_HOSTS = {
    "devguide.python.org",
    "peps.python.org",
    "www.python.org",
    "docs.python.org",
    "packages.ubuntu.com",
    "formulae.brew.sh",
    "packages.debian.org",
}


def fail(message: str) -> None:
    raise AssertionError(message)


def load_json(path: Path) -> dict:
    if not path.is_file():
        fail(f"required file missing: {path.relative_to(ROOT)}")
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def require_text(path: Path, *needles: str) -> str:
    if not path.is_file():
        fail(f"adapter missing: {path.relative_to(ROOT)}")
    text = path.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            fail(f"{path.relative_to(ROOT)} is missing required contract text: {needle!r}")
    return text


def main() -> int:
    contract = load_json(CONTRACT)
    load_json(SCHEMA)

    if contract.get("schema_version") != 1:
        fail("Python version contract schema_version must be 1")
    if contract.get("environment") != "python" or contract.get("version_family") != "3.12":
        fail("contract must describe Python 3.12")
    if contract.get("research_date") != "2026-08-11":
        fail("research date changed without updating this regression contract")

    lifecycle = contract.get("lifecycle", {})
    if lifecycle.get("status") != "security":
        fail("Python 3.12 lifecycle must be security-only")
    if lifecycle.get("upstream_latest_at_research") != "3.12.13":
        fail("researched Python 3.12 baseline must remain 3.12.13 until research is refreshed")
    if lifecycle.get("minimum_upstream_security_patch") != "3.12.13":
        fail("minimum upstream security baseline must be 3.12.13")
    if lifecycle.get("source_only_security_releases") is not True:
        fail("Python 3.12 source-only security-release boundary must be explicit")
    if lifecycle.get("last_classic_binary_installer_release") != "3.12.10":
        fail("last classic Python 3.12 binary installer release must remain explicit")
    if lifecycle.get("end_of_security_support") != "2028-10":
        fail("Python 3.12 security EOL must be explicit")

    policy = contract.get("policy", {})
    for key in ("replace_system_python", "modify_global_python_aliases", "install_global_pip_packages"):
        if policy.get(key) is not False:
            fail(f"unsafe shared Python policy enabled: {key}")
    for key in ("project_virtual_environment_required", "exact_major_minor_required", "distro_security_backports_allowed"):
        if policy.get(key) is not True:
            fail(f"required shared Python policy disabled: {key}")

    verification = contract.get("verification", {})
    if (verification.get("major"), verification.get("minor")) != (3, 12):
        fail("verification major/minor must be exactly Python 3.12")
    for key in (
        "runtime_command_must_be_adapter_owned_or_package_managed",
        "venv_smoke_test",
        "pip_smoke_test_inside_venv",
    ):
        if verification.get(key) is not True:
            fail(f"verification invariant disabled: {key}")

    adapters = contract.get("adapters", {})
    expected_keys = set(EXPECTED_ACTIVE) | EXPECTED_UNSUPPORTED
    if set(adapters) != expected_keys:
        fail(f"unexpected Python 3.12 adapter set: {sorted(adapters)}")

    for adapter_id, (strategy, entrypoint) in EXPECTED_ACTIVE.items():
        adapter = adapters[adapter_id]
        if adapter.get("support") != "experimental":
            fail(f"{adapter_id}: support must remain experimental")
        if adapter.get("strategy") != strategy:
            fail(f"{adapter_id}: unexpected strategy")
        if adapter.get("entrypoint") != entrypoint:
            fail(f"{adapter_id}: unexpected entrypoint")
        if not (ROOT / entrypoint).is_file():
            fail(f"{adapter_id}: entrypoint missing")

    for adapter_id in EXPECTED_UNSUPPORTED:
        adapter = adapters[adapter_id]
        if adapter.get("support") != "unsupported" or adapter.get("strategy") != "unsupported":
            fail(f"{adapter_id}: exact Python 3.12 native path must remain unsupported")
        if len(adapter.get("reason", "")) < 20:
            fail(f"{adapter_id}: unsupported reason missing")

    windows = adapters["windows-native"]
    if windows.get("runtime_tag") != "3.12" or windows.get("minimum_runtime_patch") != "3.12.13":
        fail("Windows must resolve Python 3.12 through the manager with the 3.12.13 security floor")
    if windows.get("requires") != ["pymanager"]:
        fail("Windows adapter must require the Python Install Manager explicitly")

    ubuntu = adapters["linux-native-ubuntu-24.04"]
    wsl = adapters["wsl2-ubuntu-24.04"]
    for adapter_id, adapter in (("linux-native-ubuntu-24.04", ubuntu), ("wsl2-ubuntu-24.04", wsl)):
        if adapter.get("platform_id") != "ubuntu" or adapter.get("version_id") != "24.04":
            fail(f"{adapter_id}: only Ubuntu 24.04 may inherit this APT contract")
        if adapter.get("packages") != ["python3.12", "python3.12-venv"]:
            fail(f"{adapter_id}: unexpected APT package set")
        if adapter.get("version_policy") != "distribution-security-backports":
            fail(f"{adapter_id}: distro security-backport policy is required")
        if "minimum_runtime_patch" in adapter:
            fail(f"{adapter_id}: upstream patch floor must not be applied to distro-backported package versions")

    macos = adapters["macos-native"]
    if macos.get("formula") != "python@3.12" or macos.get("minimum_runtime_patch") != "3.12.13":
        fail("macOS must use Homebrew python@3.12 with the researched 3.12.13 floor")

    windows_text = require_text(
        ROOT / windows["entrypoint"],
        "pymanager",
        "list --online --one --format=json",
        "install --dry-run",
        "--only-managed --one --format=exe",
        "-Experimental",
        "-m venv",
        "-m pip --version",
    )
    if "3.12.10.exe" in windows_text or "python-3.12.10" in windows_text:
        fail("Windows adapter must not fall back to the obsolete classic 3.12.10 installer")

    linux_text = require_text(
        ROOT / ubuntu["entrypoint"],
        'ID:-}" = "ubuntu"',
        'VERSION_ID:-}" = "24.04"',
        "python3.12-venv",
        "apt-get update",
        "--no-install-recommends",
        "--experimental",
        "dpkg-query",
        "-m venv",
        "-m pip --version",
    )
    if "apt-get upgrade" in linux_text or "dist-upgrade" in linux_text:
        fail("Python adapter must not perform unrelated OS upgrades")

    wsl_text = require_text(
        ROOT / wsl["entrypoint"],
        "microsoft|wsl",
        "DEVKIT_WULF_ALLOW_WSL=1",
        "DEVKIT_WULF_REQUIRE_WSL=1",
        "../../linux/environments",
    )
    if "apt-get install" in wsl_text:
        fail("WSL wrapper should reuse the exact Ubuntu Linux implementation rather than duplicate APT mutation logic")

    macos_text = require_text(
        ROOT / macos["entrypoint"],
        "python@3.12",
        "HOMEBREW_NO_AUTO_UPDATE=1",
        "--experimental",
        "brew install",
        "-m venv",
        "-m pip --version",
    )
    if "brew upgrade" in macos_text:
        fail("existing Homebrew Python must not be silently upgraded by this initial adapter")

    sources = contract.get("sources", [])
    if len(sources) < 8:
        fail("research source set is incomplete")
    for source in sources:
        parsed = urlparse(source)
        if parsed.scheme != "https" or parsed.hostname not in ALLOWED_SOURCE_HOSTS:
            fail(f"unapproved research source: {source}")

    print("Python 3.12 system-native contract: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, json.JSONDecodeError) as exc:
        print(f"Python 3.12 system-native contract: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

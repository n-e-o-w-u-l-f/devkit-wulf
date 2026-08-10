#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "manifests" / "environments.json"
PLATFORM_PATH = ROOT / "manifests" / "platforms.json"
PROFILE_PATH = ROOT / "profiles" / "profiles.json"

SUPPORT = {"native", "wsl2", "vm", "container", "source", "target-only", "experimental", "unsupported"}
STRATEGIES = {"package-manager", "winget", "official-script", "official-archive", "xcode", "wsl2", "vm", "container", "source", "target-only", "manual", "unsupported"}


def load(path: Path):
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def assert_https(url: str) -> None:
    parsed = urlparse(url)
    assert parsed.scheme == "https" and parsed.netloc, f"non-HTTPS or invalid source URL: {url}"


def main() -> None:
    env_catalog = load(ENV_PATH)
    platforms = load(PLATFORM_PATH)
    profiles = load(PROFILE_PATH)

    assert env_catalog["schema_version"] == 1
    assert platforms["schema_version"] == 1
    assert profiles["schema_version"] == 1

    platform_ids = set(platforms["platforms"])
    families = {entry["family"] for entry in platforms["platforms"].values()}
    valid_platform_keys = platform_ids | families

    envs = env_catalog["environments"]
    assert envs, "environment catalog must not be empty"

    for env_id, env in envs.items():
        assert env_id == env_id.lower(), f"environment id must be lowercase: {env_id}"
        assert env.get("name")
        assert env.get("category")
        assert env.get("platforms"), f"{env_id}: platforms required"
        assert env.get("verify"), f"{env_id}: verification commands required"
        assert env.get("sources"), f"{env_id}: sources required"

        for source in env["sources"]:
            assert_https(source)

        for platform_key, entry in env["platforms"].items():
            assert platform_key in valid_platform_keys, f"{env_id}: unknown platform/family key {platform_key}"
            assert entry["support"] in SUPPORT, f"{env_id}/{platform_key}: invalid support"
            assert entry["strategy"] in STRATEGIES, f"{env_id}/{platform_key}: invalid strategy"
            if entry["support"] == "unsupported":
                assert entry["strategy"] == "unsupported", f"{env_id}/{platform_key}: unsupported must fail closed"
            if entry["support"] == "target-only":
                assert entry["strategy"] == "target-only", f"{env_id}/{platform_key}: target-only must not be host install"
            if "architectures" in entry:
                assert len(entry["architectures"]) == len(set(entry["architectures"])), f"{env_id}/{platform_key}: duplicate architectures"

        for manager, packages in env.get("packages", {}).items():
            assert packages, f"{env_id}/{manager}: empty package list"
            assert len(packages) == len(set(packages)), f"{env_id}/{manager}: duplicate package"
            for package in packages:
                assert package.strip() == package and "\n" not in package, f"{env_id}/{manager}: malformed package token"
                assert not any(x in package for x in (";", "&&", "||", "|")), f"{env_id}/{manager}: command syntax in package token"

        for domain, script in env.get("remote_scripts", {}).items():
            assert domain in {"unix", "windows"}
            assert_https(script["url"])
            assert script["interpreter"] in {"sh", "bash", "pwsh"}
            joined_args = " ".join(script.get("arguments", []))
            assert "skip-verify" not in joined_args.lower(), f"{env_id}: verification bypass encoded in arguments"

    # Hard policy checks derived from current upstream research.
    android = envs["android"]
    assert android["platforms"]["windows"]["architectures"] == ["amd64"], "Android Studio Windows ARM must not be advertised"
    for family in ("debian", "arch", "fedora", "rhel", "opensuse"):
        assert android["platforms"][family]["architectures"] == ["amd64"], f"Android Studio Linux ARM must not be advertised for {family}"

    apple = envs["apple"]
    assert apple["platforms"]["windows"]["support"] == "unsupported"
    assert apple["platforms"]["macos"]["strategy"] == "xcode"

    go = envs["go"]
    assert go.get("cross_targets"), "Go cross targets must be represented separately from host support"
    assert "aix/ppc64" in go["cross_targets"]

    for profile_name, profile in profiles["profiles"].items():
        assert profile["environments"], f"profile {profile_name} is empty"
        missing = [env_id for env_id in profile["environments"] if env_id not in envs]
        assert not missing, f"profile {profile_name} references unknown environments: {missing}"

    # Pre-1.0 rule: no platform is promoted merely by adding an installer mapping.
    promoted = []
    for env_id, env in envs.items():
        for platform_key, entry in env["platforms"].items():
            if entry["support"] in {"native", "wsl2", "vm", "container", "source"}:
                promoted.append(f"{env_id}/{platform_key}:{entry['support']}")
    assert not promoted, f"support promoted before validation gates: {promoted}"

    print(f"validated {len(envs)} environments, {len(platforms['platforms'])} platforms, {len(profiles['profiles'])} profiles")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "manifests" / "repositories.json"
ENV_PATH = ROOT / "manifests" / "environments.json"
PLATFORM_PATH = ROOT / "manifests" / "platforms.json"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def assert_https(value: str) -> None:
    parsed = urlparse(value)
    assert parsed.scheme == "https" and parsed.netloc, f"invalid HTTPS URL: {value}"


def environment_entry(env: dict, platform_or_family: str) -> dict:
    return env.get("platforms", {}).get(platform_or_family, {})


def main() -> None:
    catalog = load(CATALOG_PATH)
    environments = load(ENV_PATH)["environments"]
    platforms = load(PLATFORM_PATH)["platforms"]

    assert catalog["schema_version"] == 1
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", catalog["research_date"])

    family_package_managers: dict[str, set[str]] = {}
    for platform_id, platform in platforms.items():
        family_package_managers.setdefault(platform["family"], set()).add(platform["package_manager"])

    for env_id, repository in catalog["repositories"].items():
        assert env_id in environments, f"repository mapping references unknown environment: {env_id}"
        env = environments[env_id]
        assert repository["publisher"].strip()

        for family, target in repository["targets"].items():
            env_entry = environment_entry(env, family)
            assert env_entry, f"{env_id}/{family}: repository mapping has no environment support entry"
            assert env_entry["support"] not in {"unsupported", "target-only"}, (
                f"{env_id}/{family}: repository mapping must not activate unsupported/target-only support"
            )
            assert env_entry["strategy"] in {"manual", "vendor-repository"}, (
                f"{env_id}/{family}: repository mapping expected manual/vendor-repository declaration"
            )
            assert target["package_manager"] in family_package_managers.get(family, set()), (
                f"{env_id}/{family}: package manager {target['package_manager']} does not match platform family"
            )
            assert_https(target["documentation"])
            assert target["tls_verification_required"] is True
            assert target["package_signature_required"] is True
            assert target["repository_file"].startswith("/")
            assert target["repository_content"]
            assert "sslverify=0" not in target["repository_content"]
            assert "gpgcheck=0" not in target["repository_content"]

            seen_destinations: set[str] = set()
            for key in target["keys"]:
                assert_https(key["url"])
                assert key["transform"] in {"copy", "gpg-dearmor", "repository-key"}
                destination = key.get("destination")
                if key["transform"] in {"copy", "gpg-dearmor"}:
                    assert destination and destination.startswith("/")
                if destination:
                    assert destination not in seen_destinations, f"{env_id}/{family}: duplicate key destination"
                    seen_destinations.add(destination)

    for env_id, platform_entries in catalog["native_packages"].items():
        assert env_id in environments, f"native package mapping references unknown environment: {env_id}"
        env = environments[env_id]
        for platform_id, native in platform_entries.items():
            assert platform_id in platforms, f"{env_id}: unknown native-package platform {platform_id}"
            assert native["package_manager"] == platforms[platform_id]["package_manager"], (
                f"{env_id}/{platform_id}: native package manager does not match platform manifest"
            )
            env_entry = environment_entry(env, platform_id)
            if not env_entry:
                env_entry = environment_entry(env, platforms[platform_id]["family"])
            assert env_entry, f"{env_id}/{platform_id}: native package mapping has no environment support entry"
            assert env_entry["support"] not in {"unsupported", "target-only"}
            assert env_entry["strategy"] in {"manual", "package-manager"}
            assert_https(native["documentation"])

    opentofu = catalog["repositories"]["opentofu"]
    assert opentofu["publisher"] == "OpenTofu / Linux Foundation"
    targets = opentofu["targets"]
    assert set(targets) == {"debian", "rhel", "opensuse"}

    for target in targets.values():
        assert target["package"] == "tofu"

    debian = targets["debian"]
    assert debian["package_manager"] == "apt"
    assert debian["repository_signature_required"] is True
    assert "signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg" in debian["repository_content"]
    assert [k["transform"] for k in debian["keys"]] == ["copy", "gpg-dearmor"]

    rhel = targets["rhel"]
    assert rhel["package_manager"] == "dnf"
    assert rhel["repository_signature_required"] is False
    assert "repo_gpgcheck=0" in rhel["repository_content"]
    assert "gpgcheck=1" in rhel["repository_content"]
    assert "sslverify=1" in rhel["repository_content"]

    opensuse = targets["opensuse"]
    assert opensuse["package_manager"] == "zypper"
    assert opensuse["repository_signature_required"] is True
    assert "repo_gpgcheck=1" in opensuse["repository_content"]
    assert "gpgcheck=1" in opensuse["repository_content"]
    assert "sslverify=1" in opensuse["repository_content"]

    fedora = catalog["native_packages"]["opentofu"]["fedora"]
    assert fedora["package_manager"] == "dnf"
    assert fedora["package"] == "opentofu"
    assert_https(fedora["documentation"])

    serialized = json.dumps(catalog).lower()
    assert "skip-verify" not in serialized
    assert "--insecure" not in serialized
    assert "sslverify=0" not in serialized

    print("validated vendor repository/native-package mappings against environment and platform contracts")


if __name__ == "__main__":
    main()

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


def packages_for(entry: dict) -> list[str]:
    if "package" in entry:
        return [entry["package"]]
    return list(entry.get("packages", []))


def normalized_fingerprint(value: str) -> str:
    return re.sub(r"\s+", "", value).upper()


def assert_no_disabled_security(content: str, label: str) -> None:
    for raw_line in content.splitlines():
        line = raw_line.strip().lower()
        assert line != "gpgcheck=0", f"{label}: package signature verification disabled"
        assert line != "sslverify=0", f"{label}: TLS verification disabled"


def target_scope(target_id: str) -> tuple[str, str]:
    scope, sep, value = target_id.partition(":")
    assert sep and scope in {"platform", "family"} and value, f"invalid repository target scope: {target_id}"
    return scope, value


def main() -> None:
    catalog = load(CATALOG_PATH)
    environments = load(ENV_PATH)["environments"]
    platforms = load(PLATFORM_PATH)["platforms"]

    assert catalog["schema_version"] == 2
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", catalog["research_date"])

    family_package_managers: dict[str, set[str]] = {}
    known_families: set[str] = set()
    for platform in platforms.values():
        known_families.add(platform["family"])
        family_package_managers.setdefault(platform["family"], set()).add(platform["package_manager"])

    for env_id, repository in catalog["repositories"].items():
        assert env_id in environments, f"repository mapping references unknown environment: {env_id}"
        env = environments[env_id]
        assert repository["publisher"].strip()

        for target_id, target in repository["targets"].items():
            scope, value = target_scope(target_id)
            if scope == "platform":
                assert value in platforms, f"{env_id}/{target_id}: unknown platform"
                platform = platforms[value]
                expected_pms = {platform["package_manager"]}
                env_entry = environment_entry(env, value) or environment_entry(env, platform["family"])
            else:
                assert value in known_families, f"{env_id}/{target_id}: unknown platform family"
                expected_pms = family_package_managers[value]
                env_entry = environment_entry(env, value)

            assert env_entry, f"{env_id}/{target_id}: repository mapping has no environment support entry"
            assert env_entry["support"] not in {"unsupported", "target-only"}, (
                f"{env_id}/{target_id}: repository mapping must not activate unsupported/target-only support"
            )
            assert env_entry["strategy"] in {"manual", "vendor-repository"}, (
                f"{env_id}/{target_id}: repository mapping expected manual/vendor-repository declaration"
            )
            assert target["package_manager"] in expected_pms, (
                f"{env_id}/{target_id}: package manager {target['package_manager']} does not match scope"
            )
            assert packages_for(target), f"{env_id}/{target_id}: at least one package required"
            assert len(packages_for(target)) == len(set(packages_for(target)))
            assert_https(target["documentation"])
            assert target["tls_verification_required"] is True
            assert target["package_signature_required"] is True
            assert target["repository_file"].startswith("/")

            repo_source_fields = [
                name
                for name in ("repository_content", "repository_content_template", "repository_url")
                if name in target
            ]
            assert len(repo_source_fields) == 1, f"{env_id}/{target_id}: exactly one repository source required"
            if "repository_url" in target:
                assert_https(target["repository_url"])
                assert target.get("repository_required_substrings"), (
                    f"{env_id}/{target_id}: remote repository file requires security assertions"
                )
            else:
                content = target.get("repository_content") or target.get("repository_content_template") or ""
                assert content
                assert_no_disabled_security(content, f"{env_id}/{target_id}")

            if "repository_content_template" in target:
                allowed = {"{suite}", "{architecture}"}
                placeholders = set(re.findall(r"\{[a-z_]+\}", target["repository_content_template"]))
                assert placeholders <= allowed, f"{env_id}/{target_id}: unsupported template placeholders {placeholders}"
                if "{suite}" in placeholders:
                    assert target.get("suite_resolver") in {"debian-codename", "ubuntu-codename"}
                if "{architecture}" in placeholders:
                    assert target.get("architecture_resolver") == "dpkg"

            if "architectures" in target:
                assert len(target["architectures"]) == len(set(target["architectures"]))
            if "supported_versions" in target:
                assert len(target["supported_versions"]) == len(set(target["supported_versions"]))

            seen_destinations: set[str] = set()
            for key in target["keys"]:
                assert_https(key["url"])
                assert key["transform"] in {"copy", "gpg-dearmor", "repository-key"}
                destination = key.get("destination")
                if key["transform"] in {"copy", "gpg-dearmor"}:
                    assert destination and destination.startswith("/")
                if destination:
                    assert destination not in seen_destinations, f"{env_id}/{target_id}: duplicate key destination"
                    seen_destinations.add(destination)
                if "fingerprint" in key:
                    assert re.fullmatch(r"[A-F0-9]{40}", normalized_fingerprint(key["fingerprint"])), (
                        f"{env_id}/{target_id}: expected fingerprint must normalize to 40 hex characters"
                    )

            for conflict in target.get("conflicting_packages", []):
                assert conflict not in packages_for(target), f"{env_id}/{target_id}: install package also listed as conflict"

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
            assert packages_for(native)
            assert_https(native["documentation"])

    # OpenTofu regression contract from the v1 repository layer.
    opentofu = catalog["repositories"]["opentofu"]
    assert opentofu["publisher"] == "OpenTofu / Linux Foundation"
    tofu_targets = opentofu["targets"]
    assert set(tofu_targets) == {"family:debian", "family:rhel", "family:opensuse"}
    assert all(target["package"] == "tofu" for target in tofu_targets.values())

    tofu_debian = tofu_targets["family:debian"]
    assert tofu_debian["package_manager"] == "apt"
    assert tofu_debian["repository_signature_required"] is True
    assert "signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg" in tofu_debian["repository_content"]
    assert [k["transform"] for k in tofu_debian["keys"]] == ["copy", "gpg-dearmor"]

    tofu_rhel = tofu_targets["family:rhel"]
    assert tofu_rhel["package_manager"] == "dnf"
    assert tofu_rhel["repository_signature_required"] is False
    assert any(line.strip() == "repo_gpgcheck=0" for line in tofu_rhel["repository_content"].splitlines())
    assert any(line.strip() == "gpgcheck=1" for line in tofu_rhel["repository_content"].splitlines())
    assert any(line.strip() == "sslverify=1" for line in tofu_rhel["repository_content"].splitlines())

    tofu_opensuse = tofu_targets["family:opensuse"]
    assert tofu_opensuse["repository_signature_required"] is True
    assert any(line.strip() == "repo_gpgcheck=1" for line in tofu_opensuse["repository_content"].splitlines())

    # Docker's tested-vendor paths are intentionally platform-specific so
    # derivatives don't inherit a vendor claim solely from a family match.
    docker = catalog["repositories"]["docker"]
    assert docker["publisher"] == "Docker, Inc."
    docker_targets = docker["targets"]
    assert set(docker_targets) == {
        "platform:debian",
        "platform:ubuntu",
        "platform:fedora",
        "platform:rhel",
    }
    expected_docker_packages = {
        "docker-ce",
        "docker-ce-cli",
        "containerd.io",
        "docker-buildx-plugin",
        "docker-compose-plugin",
    }
    assert all(set(packages_for(target)) == expected_docker_packages for target in docker_targets.values())

    docker_debian = docker_targets["platform:debian"]
    assert docker_debian["supported_versions"] == ["11", "12", "13"]
    assert set(docker_debian["architectures"]) == {"amd64", "armv7", "arm64", "ppc64le"}
    assert docker_debian["suite_resolver"] == "debian-codename"
    assert docker_debian["architecture_resolver"] == "dpkg"

    docker_ubuntu = docker_targets["platform:ubuntu"]
    assert docker_ubuntu["supported_versions"] == ["22.04", "24.04", "25.10", "26.04"]
    assert set(docker_ubuntu["architectures"]) == {"amd64", "armv7", "arm64", "ppc64le", "s390x"}
    assert docker_ubuntu["suite_resolver"] == "ubuntu-codename"

    expected_fingerprint = "060A61C51B558A7F742B77AAC52FEB6B621E9F35"
    for platform_id in ("fedora", "rhel"):
        target = docker_targets[f"platform:{platform_id}"]
        assert target["repository_url"] == f"https://download.docker.com/linux/{platform_id}/docker-ce.repo"
        assert normalized_fingerprint(target["keys"][0]["fingerprint"]) == expected_fingerprint
        assert "gpgcheck=1" in target["repository_required_substrings"]
        assert f"https://download.docker.com/linux/{platform_id}/gpg" in target["repository_required_substrings"]
        assert target["services"] == [{"name": "docker", "action": "enable-now"}]

    assert docker_targets["platform:fedora"]["supported_versions"] == ["43", "44"]
    assert set(docker_targets["platform:fedora"]["architectures"]) == {"amd64", "arm64", "ppc64le"}
    assert docker_targets["platform:rhel"]["supported_versions"] == ["8", "9", "10"]
    assert set(docker_targets["platform:rhel"]["architectures"]) == {"amd64", "arm64", "s390x"}

    docker_native = catalog["native_packages"]["docker"]
    assert set(docker_native) == {"opensuse-leap", "opensuse-tumbleweed"}
    assert all(entry["package_manager"] == "zypper" and entry["package"] == "docker" for entry in docker_native.values())

    serialized = json.dumps(catalog).lower()
    assert "skip-verify" not in serialized
    assert "--insecure" not in serialized
    assert "sslverify=0" not in serialized

    print("validated repository v2 contracts for OpenTofu and Docker")


if __name__ == "__main__":
    main()

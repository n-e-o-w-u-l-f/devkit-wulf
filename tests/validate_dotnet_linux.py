#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "manifests/dotnet-linux.json").read_text())

assert manifest["schema_version"] == 1
assert manifest["sdk_major"] == "10.0"
assert manifest["support"] == "experimental"
assert set(manifest["targets"]) == {"debian", "fedora", "rhel", "opensuse-leap"}

expected_versions = {
    "debian": {"12", "13"},
    "fedora": {"43", "44"},
    "rhel": {"8", "9", "10"},
    "opensuse-leap": {"16"},
}
expected_sources = {
    "debian": "microsoft",
    "fedora": "distribution",
    "rhel": "distribution-appstream",
    "opensuse-leap": "microsoft",
}
expected_managers = {
    "debian": "apt",
    "fedora": "dnf",
    "rhel": "dnf",
    "opensuse-leap": "zypper",
}

for platform, target in manifest["targets"].items():
    assert set(target["versions"]) == expected_versions[platform], platform
    assert target["package_source"] == expected_sources[platform], platform
    assert target["package_manager"] == expected_managers[platform], platform
    assert target["sdk_package"] == "dotnet-sdk-10.0"
    assert target["package_signature_required"] is True
    assert target["repository_signature_required"] is True
    assert target["tls_verification_required"] is True
    for version, entry in target["versions"].items():
        assert entry["architectures"], (platform, version)
        assert len(entry["architectures"]) == len(set(entry["architectures"]))
        if target["package_source"] == "microsoft":
            repo = entry.get("repository")
            assert repo, (platform, version)
            assert repo["base_url"].startswith("https://packages.microsoft.com/")
            assert repo["key_url"].startswith("https://packages.microsoft.com/keys/")
            normalized = repo["key_fingerprint"].replace(" ", "")
            assert len(normalized) == 40
            int(normalized, 16)
        else:
            assert "repository" not in entry, (platform, version)

assert manifest["targets"]["debian"]["versions"]["12"]["repository"]["suite"] == "bookworm"
assert manifest["targets"]["debian"]["versions"]["13"]["repository"]["suite"] == "trixie"
assert manifest["targets"]["debian"]["versions"]["12"]["repository"]["key_url"].endswith("microsoft.asc")
assert manifest["targets"]["debian"]["versions"]["13"]["repository"]["key_url"].endswith("microsoft-2025.asc")
assert manifest["targets"]["opensuse-leap"]["versions"]["16"]["architectures"] == ["amd64", "arm64"]
assert manifest["targets"]["rhel"]["subscription_required"] is True
assert set(manifest["targets"]["rhel"]["versions"]["10"]["architectures"]) == {"amd64", "arm64", "s390x", "ppc64le"}

print(".NET Linux adapter semantic validation passed")

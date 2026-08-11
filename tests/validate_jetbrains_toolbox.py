#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests" / "jetbrains-toolbox.json"
ENVIRONMENTS = ROOT / "manifests" / "environments.json"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def https_host(url: str) -> str:
    parsed = urlparse(url)
    assert parsed.scheme == "https" and parsed.netloc, f"invalid HTTPS URL: {url}"
    return parsed.hostname or ""


def main() -> None:
    manifest = load(MANIFEST)
    environments = load(ENVIRONMENTS)["environments"]

    assert manifest["schema_version"] == 1
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", manifest["research_date"])
    assert manifest["publisher"] == "JetBrains s.r.o."
    assert manifest["product_code"] == "TBA"
    assert manifest["release_type"] == "release"
    assert manifest["api_url"] == "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
    assert https_host(manifest["api_url"]) == "data.services.jetbrains.com"
    re.compile(manifest["version_pattern"])
    assert set(manifest["allowed_download_hosts"]) == {
        "download.jetbrains.com",
        "download-cdn.jetbrains.com",
    }

    assert set(manifest["targets"]) == {"linux"}
    linux = manifest["targets"]["linux"]
    assert linux["archive_format"] == "tar.gz"
    assert linux["destination_template"] == "{home}/.local/bin/jetbrains-toolbox"
    assert linux["path_directory_template"] == "{home}/.local/bin"
    assert linux["marker_template"] == "{home}/.local/bin/.jetbrains-toolbox.devkit-wulf.json"
    assert linux["root_directory_template"] == "jetbrains-toolbox-{version}"
    assert linux["executable_relative_path"] == "jetbrains-toolbox"
    assert set(linux["architectures"]) == {"amd64", "arm64"}
    assert linux["architectures"]["amd64"]["download_key"] == "linux"
    assert linux["architectures"]["arm64"]["download_key"] == "linuxARM64"

    jetbrains = environments["jetbrains"]
    for platform in ("debian", "arch", "fedora", "rhel", "opensuse"):
        entry = jetbrains["platforms"][platform]
        assert entry["support"] == "experimental"
        assert entry["strategy"] == "official-archive"
        assert set(entry["architectures"]) == {"amd64", "arm64"}

    # Existing native domains are intentionally not replaced by this POSIX archive helper.
    assert jetbrains["platforms"]["windows"]["strategy"] == "winget"
    assert jetbrains["platforms"]["macos"]["strategy"] == "package-manager"

    serialized = json.dumps(manifest).lower()
    assert "skip-verify" not in serialized
    assert "--insecure" not in serialized
    assert "http://" not in serialized

    print("validated JetBrains Toolbox Linux amd64/arm64 artifact contract")


if __name__ == "__main__":
    main()

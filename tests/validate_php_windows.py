#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests" / "php-windows.json"
ENVIRONMENTS = ROOT / "manifests" / "environments.json"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    manifest = load(MANIFEST)
    envs = load(ENVIRONMENTS)["environments"]

    assert manifest["schema_version"] == 1
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", manifest["research_date"])
    assert manifest["publisher"] == "PHP Group"
    assert manifest["release_index_url"] == "https://windows.php.net/downloads/releases/releases.json"
    assert manifest["download_base_url"] == "https://windows.php.net/downloads/releases"
    for url in (manifest["release_index_url"], manifest["download_base_url"]):
        parsed = urlparse(url)
        assert parsed.scheme == "https" and parsed.hostname == "windows.php.net"
    re.compile(manifest["version_pattern"])
    re.compile(manifest["build_pattern"])
    assert manifest["branch_policy"] == "latest-stable-branch"

    target = manifest["target"]
    assert target["platform"] == "windows"
    assert target["architecture"] == "amd64"
    assert target["destination_template"] == r"{localappdata}\devkit-wulf\php"
    assert target["path_directory_template"] == r"{localappdata}\devkit-wulf\php"
    assert target["marker_name"] == ".devkit-wulf-artifact.json"
    assert target["archive_format"] == "zip"
    assert target["php_executable"] == "php.exe"
    assert target["integrity"] == "sha256-release-metadata"
    assert target["thread_safety"] == "nts"
    assert target["privileged"] is False

    php = envs["php"]
    windows = php["platforms"]["windows"]
    assert windows["support"] == "experimental"
    assert windows["strategy"] == "official-archive"
    assert windows["architectures"] == ["amd64"]
    assert "php --version" in php["verify"]
    assert "composer --version" in php["verify"], (
        "PHP Windows runtime helper must not be centrally activated until Composer is also satisfied"
    )

    serialized = json.dumps(manifest).lower()
    assert "skip-verify" not in serialized
    assert "--insecure" not in serialized
    assert "http://" not in serialized

    print("validated PHP Windows amd64 NTS archive contract; Composer remains a separate integration gate")


if __name__ == "__main__":
    main()

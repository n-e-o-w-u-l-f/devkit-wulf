#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests" / "composer-windows.json"
ENVIRONMENTS = ROOT / "manifests" / "environments.json"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    manifest = load(MANIFEST)
    envs = load(ENVIRONMENTS)["environments"]
    assert manifest["schema_version"] == 1
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", manifest["research_date"])
    assert manifest["publisher"] == "Composer"
    assert manifest["phar_url"] == "https://getcomposer.org/download/latest-stable/composer.phar"
    assert manifest["checksum_url"] == "https://getcomposer.org/download/latest-stable/composer.phar.sha256sum"
    for url in (manifest["phar_url"], manifest["checksum_url"]):
        parsed = urlparse(url)
        assert parsed.scheme == "https" and parsed.hostname == "getcomposer.org"
    re.compile(manifest["version_pattern"])

    target = manifest["target"]
    assert target["platform"] == "windows"
    assert target["architecture"] == "amd64"
    assert target["php_directory_template"] == r"{localappdata}\devkit-wulf\php"
    assert target["php_executable"] == "php.exe"
    assert target["php_marker"] == ".devkit-wulf-artifact.json"
    assert target["phar_name"] == "composer.phar"
    assert target["wrapper_name"] == "composer.bat"
    assert target["marker_name"] == ".devkit-wulf-composer.json"
    assert target["integrity"] == "sha256-double-read"
    assert target["privileged"] is False
    assert target["path_mutation"] is False

    php = envs["php"]
    windows = php["platforms"]["windows"]
    assert windows["support"] == "experimental"
    assert windows["strategy"] == "official-archive"
    assert windows["architectures"] == ["amd64"]
    assert "php --version" in php["verify"]
    assert "composer --version" in php["verify"]

    serialized = json.dumps(manifest).lower()
    assert "skip-verify" not in serialized
    assert "--insecure" not in serialized
    assert "http://" not in serialized

    print("validated Composer Windows stable PHAR contract and PHP environment cross-gate")


if __name__ == "__main__":
    main()

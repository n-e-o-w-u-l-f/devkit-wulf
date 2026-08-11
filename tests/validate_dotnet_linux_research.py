#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests" / "dotnet-linux-research.json"
PLATFORMS = ROOT / "manifests" / "platforms.json"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    manifest = load(MANIFEST)
    platforms = load(PLATFORMS)["platforms"]

    assert manifest["schema_version"] == 1
    assert manifest["publisher"] == "Microsoft"
    assert manifest["product"] == ".NET"
    assert manifest["activation"] is False
    assert set(manifest["targets"]) == {"debian", "fedora", "rhel", "opensuse-leap"}

    for key, target in manifest["targets"].items():
        assert target["scope"] == "platform"
        assert target["platform_id"] == key
        assert key in platforms
        assert target["status"] == "research-only"
        parsed = urlparse(target["documentation"])
        assert parsed.scheme == "https" and parsed.hostname == "learn.microsoft.com"

    policies = "\n".join(manifest["non_inheritance_policy"]).lower()
    assert "derivatives do not inherit" in policies
    assert "package-manager compatibility alone never activates" in policies
    assert len(manifest["activation_requirements"]) >= 7

    serialized = json.dumps(manifest).lower()
    assert "skip-verify" not in serialized
    assert "--insecure" not in serialized
    assert '"activation": true' not in serialized

    print("validated fail-closed .NET Linux research contract")


if __name__ == "__main__":
    main()

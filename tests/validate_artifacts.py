#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_PATH = ROOT / "manifests" / "artifacts.json"
ENV_PATH = ROOT / "manifests" / "environments.json"
ALLOWED_ARCHES = {"amd64", "arm64", "armv7", "riscv64", "ppc64", "ppc64le", "s390x", "sparc64"}


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def assert_https(value: str) -> None:
    parsed = urlparse(value.replace("{version}", "v0.0.0"))
    assert parsed.scheme == "https" and parsed.netloc, f"invalid HTTPS URL/template: {value}"


def main() -> None:
    catalog = load(ARTIFACT_PATH)
    envs = load(ENV_PATH)["environments"]
    assert catalog["schema_version"] == 1
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", catalog["research_date"])
    assert catalog["artifacts"]

    for env_id, artifact in catalog["artifacts"].items():
        assert env_id in envs
        assert artifact["publisher"].strip()
        assert_https(artifact["source"])
        resolver = artifact["version"]
        assert resolver["resolver"] == "text-url"
        assert_https(resolver["url"])
        re.compile(resolver["pattern"])
        assert any(entry["strategy"] == "official-archive" for entry in envs[env_id]["platforms"].values())

        for target_name, target in artifact["targets"].items():
            assert target_name.strip()
            assert target["destination"].startswith("/")
            assert target["path_directory"].startswith("/")
            assert re.fullmatch(r"0[0-7]{3}", target["mode"])
            assert target["integrity"] == "sha256"
            assert isinstance(target["privileged"], bool)
            assert target["architectures"]
            for arch, entry in target["architectures"].items():
                assert arch in ALLOWED_ARCHES
                assert re.fullmatch(r"[A-Za-z0-9._+-]+", entry["filename"])
                for field in ("url_template", "checksum_url_template"):
                    value = entry[field]
                    assert_https(value)
                    assert value.count("{version}") == 1

    kubectl = catalog["artifacts"]["kubectl"]
    assert kubectl["version"]["url"] == "https://dl.k8s.io/release/stable.txt"
    linux = kubectl["targets"]["linux"]
    assert linux["privileged"] is True
    assert set(linux["architectures"]) == {"amd64", "arm64"}
    for arch in ("amd64", "arm64"):
        assert linux["architectures"][arch]["url_template"] == f"https://dl.k8s.io/release/{{version}}/bin/linux/{arch}/kubectl"
        assert linux["architectures"][arch]["checksum_url_template"] == f"https://dl.k8s.io/release/{{version}}/bin/linux/{arch}/kubectl.sha256"

    print(f"validated {len(catalog['artifacts'])} verified artifact adapter(s)")


if __name__ == "__main__":
    main()

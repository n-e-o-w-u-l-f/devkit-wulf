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
    assert catalog["schema_version"] == 2
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", catalog["research_date"])
    assert catalog["artifacts"]

    for env_id, artifact in catalog["artifacts"].items():
        assert env_id in envs
        assert artifact["publisher"].strip()
        assert_https(artifact["source"])
        resolver = artifact["version"]
        assert resolver["resolver"] in {"text-url", "release-index"}
        if resolver["resolver"] == "text-url":
            assert_https(resolver["url"])
            re.compile(resolver["pattern"])
        else:
            assert resolver["channel"] in {"stable", "beta", "dev"}
            re.compile(resolver["version_pattern"])

        assert any(entry["strategy"] == "official-archive" for entry in envs[env_id]["platforms"].values())

        for target_name, target in artifact["targets"].items():
            assert target_name.strip()
            assert target["kind"] in {"binary", "archive"}
            assert target["architectures"]
            for arch, entry in target["architectures"].items():
                assert arch in ALLOWED_ARCHES
                if target["kind"] == "binary":
                    assert re.fullmatch(r"[A-Za-z0-9._+-]+", entry["filename"])
                    for field in ("url_template", "checksum_url_template"):
                        value = entry[field]
                        assert_https(value)
                        assert value.count("{version}") == 1
                else:
                    assert entry["release_arch"] in {"x64", "arm64"}

            if target["kind"] == "binary":
                assert target["destination"].startswith("/")
                assert target["path_directory"].startswith("/")
                assert re.fullmatch(r"0[0-7]{3}", target["mode"])
                assert target["integrity"] == "sha256"
                assert isinstance(target["privileged"], bool)
            else:
                assert resolver["resolver"] == "release-index", f"{env_id}/{target_name}: archive requires release-index resolver"
                assert_https(target["release_index_url"])
                assert_https(target["expected_base_url"])
                assert target["destination_template"].startswith("{home}/")
                assert target["path_directory_template"].startswith("{home}/")
                assert target["archive_format"] in {"tar.xz", "zip"}
                assert re.fullmatch(r"[A-Za-z0-9._+-]+", target["root_directory"])
                assert target["integrity"] == "sha256-release-metadata"
                assert target["privileged"] is False

    kubectl = catalog["artifacts"]["kubectl"]
    assert kubectl["version"]["url"] == "https://dl.k8s.io/release/stable.txt"
    linux = kubectl["targets"]["linux"]
    assert linux["kind"] == "binary"
    assert set(linux["architectures"]) == {"amd64", "arm64"}
    for arch in ("amd64", "arm64"):
        assert linux["architectures"][arch]["url_template"] == f"https://dl.k8s.io/release/{{version}}/bin/linux/{arch}/kubectl"
        assert linux["architectures"][arch]["checksum_url_template"] == f"https://dl.k8s.io/release/{{version}}/bin/linux/{arch}/kubectl.sha256"

    flutter = catalog["artifacts"]["flutter"]
    assert flutter["publisher"] == "Flutter / Google"
    assert flutter["version"]["resolver"] == "release-index"
    assert flutter["version"]["channel"] == "stable"
    flutter_linux = flutter["targets"]["linux"]
    flutter_macos = flutter["targets"]["macos"]
    expected_base = "https://storage.googleapis.com/flutter_infra_release/releases"
    assert flutter_linux["release_index_url"] == f"{expected_base}/releases_linux.json"
    assert flutter_macos["release_index_url"] == f"{expected_base}/releases_macos.json"
    assert flutter_linux["expected_base_url"] == expected_base
    assert flutter_macos["expected_base_url"] == expected_base
    assert set(flutter_linux["architectures"]) == {"amd64"}, "current Flutter SDK archive docs advertise Linux x64"
    assert flutter_linux["architectures"]["amd64"]["release_arch"] == "x64"
    assert set(flutter_macos["architectures"]) == {"amd64", "arm64"}
    assert flutter_macos["architectures"]["amd64"]["release_arch"] == "x64"
    assert flutter_macos["architectures"]["arm64"]["release_arch"] == "arm64"
    for target in (flutter_linux, flutter_macos):
        assert target["destination_template"] == "{home}/develop/flutter"
        assert target["path_directory_template"] == "{home}/develop/flutter/bin"

    # The artifact adapter must never broaden host support. Linux arm64 still
    # remains fail-closed at the artifact layer until upstream archive support is
    # explicitly researched and mapped.
    assert "arm64" not in flutter_linux["architectures"]

    print(f"validated {len(catalog['artifacts'])} verified artifact adapter(s), including Flutter release-index archives")


if __name__ == "__main__":
    main()

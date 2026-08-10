#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "manifests" / "repositories.json"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def assert_https(value: str) -> None:
    parsed = urlparse(value)
    assert parsed.scheme == "https" and parsed.netloc, f"invalid HTTPS URL: {value}"


def main() -> None:
    catalog = load(CATALOG_PATH)
    assert catalog["schema_version"] == 1
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", catalog["research_date"])

    opentofu = catalog["repositories"]["opentofu"]
    assert opentofu["publisher"] == "OpenTofu / Linux Foundation"
    targets = opentofu["targets"]
    assert set(targets) == {"debian", "rhel", "opensuse"}

    for name, target in targets.items():
        assert_https(target["documentation"])
        assert target["tls_verification_required"] is True
        assert target["package_signature_required"] is True
        assert target["package"] == "tofu"
        assert target["repository_file"].startswith("/")
        assert target["repository_content"]
        assert "sslverify=0" not in target["repository_content"]
        assert "gpgcheck=0" not in target["repository_content"]
        for key in target["keys"]:
            assert_https(key["url"])
            assert key["transform"] in {"copy", "gpg-dearmor", "repository-key"}
            if key["transform"] in {"copy", "gpg-dearmor"}:
                assert key.get("destination", "").startswith("/")

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

    print("validated OpenTofu vendor repository and Fedora native package metadata")


if __name__ == "__main__":
    main()

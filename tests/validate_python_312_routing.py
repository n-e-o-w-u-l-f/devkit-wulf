#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

POSIX = {
    "linux": ROOT / "installers/linux/devkit-wulf.sh",
    "wsl": ROOT / "installers/wsl/devkit-wulf.sh",
    "macos": ROOT / "installers/macos/devkit-wulf.sh",
}
WINDOWS = ROOT / "installers/windows/devkit-wulf.ps1"


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> int:
    for family, path in POSIX.items():
        text = path.read_text(encoding="utf-8")
        for required in (
            '"${2:-}" = "python@3.12"',
            'plan|install|verify',
            'environments/python-3.12.sh',
            'shift 2',
            'exec "$adapter" "$action" "$@"',
        ):
            if required not in text:
                fail(f"{family}: missing Python 3.12 routing invariant {required!r}")

        route_pos = text.find('"${2:-}" = "python@3.12"')
        core_guard_pos = text.find('[ -f "$CORE" ]')
        if route_pos < 0 or core_guard_pos < 0 or route_pos > core_guard_pos:
            fail(f"{family}: version-specific route must be resolved before generic-core existence checks")

        if 'python@3.12 supports only plan, install and verify' not in text:
            fail(f"{family}: unsupported version-route actions must fail closed")

    windows = WINDOWS.read_text(encoding="utf-8")
    for required in (
        "$Target -eq 'python@3.12'",
        "@('plan', 'install', 'verify')",
        "installers\\windows\\environments\\python-3.12.ps1",
        "-Action $Command -Experimental:$Experimental",
        "does not accept -AcceptRemoteScript, -Supported or -Platform",
    ):
        if required not in windows:
            fail(f"windows: missing Python 3.12 routing invariant {required!r}")

    route_pos = windows.find("$Target -eq 'python@3.12'")
    core_guard_pos = windows.find("Windows orchestrator core not found")
    if route_pos < 0 or core_guard_pos < 0 or route_pos > core_guard_pos:
        fail("windows: version-specific route must be resolved before generic-core existence checks")

    if "python@3.12" in (ROOT / "bin/devkit-wulf").read_text(encoding="utf-8"):
        fail("POSIX generic core must not absorb the system-native Python 3.12 route")
    if "python@3.12" in (ROOT / "bin/devkit-wulf.ps1").read_text(encoding="utf-8"):
        fail("Windows generic core must not absorb the system-native Python 3.12 route")

    print("Python 3.12 entrypoint routing: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"Python 3.12 entrypoint routing: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

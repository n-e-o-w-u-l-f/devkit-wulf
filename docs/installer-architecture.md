# System-native installer architecture

Research/architecture date: **2026-08-11**

## Decision

`devkit-wulf` does **not** ship one universal installer artifact for every operating system.

Environment intent may be shared, but executable installer entrypoints and release formats are system-native. A Windows `.exe` or `.msi` is a Windows artifact and is never presented as something Debian, Fedora, macOS, BSD, Solaris/illumos or AIX can execute. Likewise, Debian/RPM/Arch/Alpine packages are not Windows artifacts.

The machine-readable contract is `manifests/installer-families.json`.

## Responsibility split

### Shared environment contracts

Shared data describes **what** an environment means:

- environment ID and display name;
- requested version or release channel;
- components/capabilities;
- dependency intent;
- security policy;
- verification semantics;
- state/ownership fields;
- cross-platform configuration that is genuinely identical.

Shared contracts may live under `environments/` as version-specific definitions are introduced.

They must not contain commands that assume a particular package manager, executable format, privilege mechanism or filesystem convention.

### System-native installer implementations

System-specific code describes **how** that environment is installed on the selected host:

- Windows: PowerShell, WinGet, MSI/EXE/MSIX or verified Windows archives as appropriate;
- Linux: POSIX shell plus the exact distribution package manager/vendor repository/verified Linux artifact;
- WSL2: Linux installer logic executed inside the selected Linux distribution, with Windows-side WSL provisioning kept separate;
- macOS: native macOS package/vendor/archive mechanisms;
- BSD: BSD-family package/source/archive mechanisms only where researched;
- Solaris/illumos: SunOS-family mechanisms only where researched;
- AIX: AIX-specific mechanisms only where researched.

A shared internal library/core is allowed when the code is portable, but the release-facing entrypoint must still prove the host family before delegating.

## Release-facing entrypoints

```text
installers/
├── windows/
│   └── devkit-wulf.ps1
├── linux/
│   └── devkit-wulf.sh
├── wsl/
│   └── devkit-wulf.sh
├── macos/
│   └── devkit-wulf.sh
├── bsd/
│   └── devkit-wulf.sh
├── solaris/
│   └── devkit-wulf.sh
└── aix/
    └── devkit-wulf.sh
```

The existing `bin/devkit-wulf` and `bin/devkit-wulf.ps1` are internal orchestration cores during the migration. They are not a claim that one binary format is executable everywhere.

## Example: Python 3.12

Python 3.12 can use one shared environment contract while still having different installer implementations.

Conceptually, the shared contract can state:

```json
{
  "environment": "python",
  "version": "3.12",
  "components": ["python", "pip", "venv"],
  "policy": {
    "replace_system_python": false,
    "project_isolation_required": true
  },
  "verification": [
    "python runtime is 3.12.x",
    "pip belongs to the selected runtime",
    "venv can create an isolated environment"
  ]
}
```

That does **not** imply one installer executable.

A future researched implementation can map that shared contract to adapters such as:

```text
environments/python/3.12.json
installers/windows/environments/python-3.12.ps1
installers/linux/environments/python-3.12.sh
installers/macos/environments/python-3.12.sh
```

The adapters may share plan/state/verification helper code where safe, but they independently resolve:

- trusted source;
- host architecture;
- package/installer format;
- dependencies;
- privilege requirements;
- PATH behavior;
- existing-install conflict policy;
- uninstall/rollback ownership.

For example, a Windows Python 3.12 adapter may eventually use an official Windows installer or trusted WinGet package, while Debian may use a distribution package, an explicitly researched vendor/source path or a verified build path. The shared contract does not force either host to imitate the other.

Version-specific adapters must not be activated until current upstream support/source/integrity research and the normal devkit-wulf gates are complete.

## WSL2 boundary

WSL2 is not treated as "Windows with Linux commands". There are two domains:

1. Windows host operations: enabling WSL, installing/converting a distribution, Windows-side integration — PowerShell/system-change contract.
2. Linux environment operations inside the WSL distribution — Linux installer contract with the actual distro/package manager detected inside WSL.

A Windows `.exe` must not be used as the normal installer inside Debian/Ubuntu/Arch/openSUSE WSL. The Linux entrypoint executes there.

## Release format policy

Examples of allowed release families:

| Family | Typical release formats |
|---|---|
| Windows native | `.ps1`, `.zip`, `.msi`, `.exe` |
| Linux native | `.sh`, `.tar.gz`, `.deb`, `.rpm`, `.pkg.tar.zst`, `.apk` |
| WSL2 Linux | Linux `.sh` / `.tar.gz` payload executed inside the distro |
| macOS | `.sh`, `.tar.gz`, `.pkg`, `.dmg` |
| BSD | `.sh`, `.tar.gz`, native package forms where researched |
| Solaris/illumos | `.sh`, `.tar.gz`, native package forms where researched |
| AIX | `.sh`, `.tar.gz` until stronger package contracts are researched |

A future compiled launcher may be produced per target OS/architecture, but it must be a **set of target-specific artifacts**, not one executable falsely labeled universal.

## Gate consequences

- GATE-01 must be performed again by the release-facing system entrypoint.
- GATE-02 resolves support inside the selected host/domain, not from a generic POSIX assumption.
- GATE-04/05 sources and integrity metadata are adapter-specific.
- GATE-07 privilege handling remains host-specific.
- GATE-08 conflicts are evaluated against the host's native installation mechanisms.
- GATE-13 prevents Windows/WSL PATH leakage.
- GATE-16 tests each installer family on an appropriate operating system or authoritative target.
- GATE-18 documentation must distinguish shared environment behavior from system-specific installation behavior.

## Migration rule

New installer work should prefer the system-native tree immediately.

Existing logic under `bin/`, `lib/` and product-specific helpers may be migrated incrementally. Migration must preserve working gates and tests; code is not moved merely for cosmetic layout changes.

The intended end state is:

```text
shared environment specification
        │
        ├── Windows adapter ── Windows release artifact
        ├── Linux adapter ──── Linux release artifact(s)
        ├── WSL adapter ────── Linux payload inside WSL
        ├── macOS adapter ──── macOS release artifact
        └── researched extended-platform adapters
```

This keeps common environment behavior aligned without pretending the operating systems have interchangeable executables or package managers.

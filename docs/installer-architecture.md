# System-native installer architecture

Research/architecture date: **2026-08-11**

## Decision

`devkit-wulf` does **not** ship one universal installer artifact for every operating system.

Environment intent may be shared, but executable installer entrypoints and release formats are system-native. A Windows `.exe`, `.msi`, PowerShell transaction, Linux package, POSIX archive, or macOS artifact is valid only in the execution domain for which it was reviewed.

The machine-readable installer-family contract is `manifests/installer-families.json`.

## Responsibility split

### Shared environment contracts

Shared data under `environments/` describes **what** a versioned environment means:

- selector/version or release channel;
- components/capabilities;
- dependency intent;
- common security policy;
- verification semantics;
- adapter inventory and explicit unsupported domains.

Shared contracts must not embed a false assumption that package managers, executable formats, privilege models, paths, or artifact layouts are portable across operating systems.

### System-native implementations

System-specific code under `installers/<family>/` describes **how** the environment is resolved in that host/domain:

- Windows: PowerShell, WinGet, or reviewed Windows-native archives/installers;
- Linux: POSIX shell plus the exact distribution package manager, vendor repository, or reviewed Linux artifact;
- WSL2: Linux installation inside the selected distribution, with Windows-side WSL provisioning kept separate;
- macOS: macOS-native package/vendor/archive mechanisms;
- BSD, Solaris/illumos, AIX: only explicitly researched mechanisms and targets.

Portable internal helpers are allowed, but the release-facing entrypoint must prove the host/domain before delegation.

## Release-facing entrypoints

```text
installers/
├── windows/devkit-wulf.ps1
├── linux/devkit-wulf.sh
├── wsl/devkit-wulf.sh
├── macos/devkit-wulf.sh
├── bsd/devkit-wulf.sh
├── solaris/devkit-wulf.sh
└── aix/devkit-wulf.sh
```

The generic `bin/devkit-wulf` and `bin/devkit-wulf.ps1` remain orchestration cores during the migration. They are not the release-format abstraction and are not evidence that one executable is portable everywhere.

## Current versioned-selector examples

The version-specific model is already implemented for several selectors.

### Python 3.12

Shared contract:

```text
environments/python/3.12.json
```

System-native adapters:

```text
installers/windows/environments/python-3.12.ps1
installers/linux/environments/python-3.12.sh
installers/wsl/environments/python-3.12.sh
installers/macos/environments/python-3.12.sh
```

Each adapter independently enforces its reviewed host/source/version/integrity policy. The shared contract does not force Windows to imitate Linux or vice versa.

### Go stable

`go@stable` demonstrates a shared selector with different artifact implementations:

```text
environments/go/stable.json

POSIX:
  manifests/go-artifact.json
  lib/go-artifact.sh

Windows:
  manifests/go-windows.json
  lib/go-windows.ps1
```

Linux, WSL2, macOS, and Windows have experimental release-facing routes. Windows uses a native ZIP/PowerShell transaction rather than reusing the POSIX tar helper. The Go workflow still contains one obsolete Windows fail-closed assertion; issue #35 tracks reconciliation.

### Rust stable

`rust@stable` is actively routed on Linux, WSL2, and macOS. A native Windows rustup manifest/helper/adapter exists and has dedicated validation, but the top-level Windows release selector intentionally continues to block the selector until the integration contract is promoted. Adapter presence therefore remains distinct from selector routing.

### Flutter stable

`flutter@stable` is experimentally routed on Linux, macOS, and native Windows amd64. WSL remains explicitly unsupported for that selector. The host implementations use the reviewed Flutter release metadata and host-appropriate archive transaction.

### kubectl staging boundary

Native macOS and Windows kubectl artifact adapters exist as direct experimental components. A shared top-level `kubectl@stable` selector has not been promoted. Direct component availability must not be documented as shared-selector support.

## WSL2 boundary

WSL2 is not treated as "Windows with Linux commands". There are two domains:

1. Windows host operations: enabling WSL, installing/converting a distribution, and Windows-side integration.
2. Linux environment operations inside the WSL distribution: the Linux installer contract for the detected distribution.

A Windows installer is not the normal toolchain installer inside Debian/Ubuntu/Arch/openSUSE WSL. The WSL release entrypoint proves the WSL domain and delegates to reviewed Linux payloads only where the shared contract explicitly allows that relationship.

## Release-format policy

| Family | Typical reviewed release forms |
| --- | --- |
| Windows native | `.ps1`, `.zip`, `.msi`, `.exe` |
| Linux native | `.sh`, `.tar.gz`, `.deb`, `.rpm`, `.pkg.tar.zst`, `.apk` |
| WSL2 Linux | Linux payload executed inside the distro |
| macOS | `.sh`, `.tar.gz`, `.zip`, `.pkg`, `.dmg` |
| BSD | `.sh`, `.tar.gz`, native package forms where researched |
| Solaris/illumos | `.sh`, `.tar.gz`, native package forms where researched |
| AIX | `.sh`, `.tar.gz`, stronger native forms only after research |

A future compiled launcher must be produced per target OS/architecture. It must never be presented as one falsely universal executable.

## Contract/routing/support rule

The following are intentionally independent:

1. a shared contract exists;
2. a native adapter exists;
3. a release-facing selector routes to that adapter;
4. all required target and governance gates pass;
5. support is explicitly promoted.

Skipping any of these distinctions is a documentation and support-state error.

## Gate consequences

- GATE-01 is re-evaluated by the release-facing system entrypoint.
- GATE-02 resolves support in the selected host/domain, never from a generic POSIX assumption.
- GATE-04/05 source and integrity metadata are adapter-specific.
- GATE-07 privilege handling is host-specific.
- GATE-08 conflicts are evaluated against the native installation mechanism and destination ownership.
- GATE-13 prevents implicit PATH/domain leakage.
- GATE-15 requires ownership-aware removal before safe removal is promoted.
- GATE-16 tests every claimed installer family on an appropriate operating system or authoritative target.
- GATE-18 keeps shared intent, native implementation, and support state synchronized in documentation.
- GATE-19 requires release integrity/SBOM evidence before a stable release claim.

## Migration rule

New installer work should prefer the system-native tree immediately. Existing logic under `bin/`, `lib/`, and product-specific helpers may be migrated incrementally when the move preserves gates and tests.

The intended architecture is:

```text
shared environment specification
        │
        ├── Windows adapter ── Windows-native transaction
        ├── Linux adapter ──── Linux-native transaction
        ├── WSL adapter ────── reviewed Linux payload inside WSL
        ├── macOS adapter ──── macOS-native transaction
        └── researched extended-platform adapters
```

See `environments/README.md`, `installers/README.md`, and `docs/REPOSITORY-STATUS.md` for the current audited boundary.

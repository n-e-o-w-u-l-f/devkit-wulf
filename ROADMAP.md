# devkit-wulf roadmap

Status date: **2026-08-11**

The roadmap distinguishes **implemented mechanics**, **staged adapters**, and **promoted support**. No environment/platform combination is promoted merely because a manifest, helper, installer, or test exists. `AGENTS.md` remains authoritative for GATE-00 through GATE-19.

For the audited current-state snapshot, see [`docs/REPOSITORY-STATUS.md`](docs/REPOSITORY-STATUS.md).

## Phase 0 — orchestration foundation

### Implemented

- repository governance contract (`AGENTS.md`);
- GATE-00 through GATE-19 definitions;
- platform, environment, profile, repository and artifact manifests/schemas;
- host/architecture detection;
- support/strategy resolver;
- plan mode;
- state/event logging;
- remote-script inspection gates;
- verification framework;
- fail-closed removal entrypoints;
- CI/security/offline-fixture definitions;
- system-native release boundary under `installers/`.

### Promotion blockers

- GitHub-hosted CI must be runnable and must execute successfully; the latest audited run was blocked before runner start by an external account/billing condition;
- machine-readable contract drift must be removed, including issue #34 (`apple`/`xcode`);
- rollback/removal ownership needs product-specific completion before safe uninstall promotion;
- package/version conflict detection must become richer for version-manager coexistence;
- the generic CLIs still lack the roadmap-level `--version` and `--target native|wsl:<distro>` resolution contract.

## Phase 1 — Windows / WSL2 / Debian / Ubuntu / Arch / macOS

### Implemented

- native Windows PowerShell orchestrator;
- WinGet adapter with installed-package detection;
- explicit WSL planning/bootstrap path;
- WSL distro discovery and no implicit WSL1 conversion;
- Linux distribution detector;
- apt/pacman adapters;
- macOS bootstrap with Xcode CLT check and gated Homebrew bootstrap;
- WSL filesystem guidance;
- release-facing versioned selectors for reviewed Python, Go, Rust and Flutter lanes where explicitly routed.

### Still gated

- environment-by-environment target-system promotion;
- reboot/resume state for WSL feature activation;
- explicit WSL distribution post-install handoff;
- deterministic top-level execution-domain selection through issue #4;
- Windows PATH refresh semantics for external installers that mutate environment variables outside the current process;
- Windows `rust@stable` central release routing: the native verified adapter/manifest exists, but the top-level Windows release selector intentionally remains gated;
- translation synchronization with the canonical English release boundary.

## Phase 2 — Fedora/RHEL / openSUSE / Alpine

### Implemented

- host detection;
- `dnf`, `zypper`, `apk` package-manager adapters;
- distro-container CI definitions;
- platform/architecture catalog entries;
- reviewed Linux .NET repository/package contracts for selected Debian, Fedora, RHEL and openSUSE targets;
- verified repository helper mechanics including key-fingerprint and conflict checks.

### Still gated

- real target/version matrix evidence across Fedora/RHEL/Rocky/Alma;
- Leap/Tumbleweed target tests;
- musl-vs-glibc compatibility validation per environment on Alpine;
- support promotion remains separate from repository/package adapter presence.

## Phase 3 — core language/toolchain environments

Catalogued:

- Base developer tools;
- C/C++;
- Python;
- Node.js;
- Java;
- .NET;
- Go;
- Rust.

### Implemented experimental versioned lanes

- `python@3.12`: native Linux, WSL2, macOS and Windows adapters/contracts;
- `go@stable`: native Linux, WSL2, macOS and Windows verified-artifact adapters/contracts;
- `rust@stable`: native Linux, WSL2 and macOS verified rustup-artifact path;
- native Windows rustup artifact helper/manifest/adapter is staged and tested but is not yet centrally routed by the Windows release selector.

The generic unversioned environments continue to use their existing package-manager, WinGet, official-script, or other declared strategies. The versioned selectors do not silently replace them.

### Still gated

- issue #4: generic version resolver and explicit native/WSL target selection;
- issue #35: update the Go Windows workflow to match the now-active experimental Windows route;
- complete compiler/toolchain smoke coverage on authoritative targets;
- product-specific safe removal and rollback ownership;
- support-state promotion after all relevant gates pass.

## Phase 4 — extended environments

Catalogued:

- Deno;
- Bun;
- PHP;
- Ruby;
- VS Code;
- Visual Studio / MSVC / Windows SDK;
- JetBrains Toolbox/IDE manager;
- Eclipse IDE;
- Android Studio / SDK;
- Flutter / Dart;
- Xcode / Apple SDKs;
- Docker;
- Podman;
- kubectl;
- OpenTofu.

### Implemented reviewed component paths

- `flutter@stable`: verified release-index/archive path on Linux, macOS and Windows; WSL remains explicitly unsupported for this selector;
- Windows PHP runtime plus Composer orchestration and verification;
- verified JetBrains Toolbox Linux artifact helper;
- macOS and Windows native kubectl artifact adapters as direct experimental components;
- verified generic artifact and repository helper mechanics;
- Docker/.NET/repository research and fail-closed contracts.

### Still gated

- Android SDK component and emulator planner;
- Visual Studio workload/channel resolver;
- JetBrains individual product selection after Toolbox installation;
- Eclipse package-flavor selection;
- Docker Engine official repository adapters/validation for every intended Linux family;
- Podman Machine lifecycle/state tracking;
- shared top-level `kubectl@stable` selector and cluster-aware version policy; direct macOS/Windows adapters alone do not constitute selector promotion;
- OpenTofu vendor repository setup on Debian/RPM families;
- issue #34: reconcile `xcode` in the environment catalog with stale `apple` references in profiles/validation;
- product-specific safe removal.

## Phase 5 — BSD family

### Implemented

- detection for FreeBSD, OpenBSD, NetBSD and DragonFly BSD;
- bootstrap for available native package managers;
- catalog strategy entries;
- fail-closed experimental/target-only distinctions.

### Promotion requirement

Each BSD/environment combination requires real or authoritative target validation. One BSD passing does not promote another. See issue #5.

## Phase 6 — illumos / Solaris / AIX

### Implemented

- host detection;
- bootstrap prerequisite paths that refuse unknown package ecosystems;
- source/target-only distinctions;
- Go cross-target separation;
- Temurin/source research evidence.

### Promotion requirement

These remain authoritative-target validation platforms. No support promotion occurs from POSIX compatibility, successful bootstrap, or cross-compilation capability alone. See issue #5.

# Release criteria

Before the first stable release:

1. required CI runners execute and all required checks pass;
2. known machine-readable and workflow contract drift is resolved;
3. at least one environment in each claimed primary platform family passes install → verify → install again → verify on authoritative targets;
4. support-state promotions are committed separately from adapter implementation;
5. integrity/signature gates are exercised by tests;
6. no critical security finding remains unresolved;
7. ownership-aware removal exists for any environment advertised as safely removable;
8. generic version/target selection is deterministic where claimed;
9. release checksum and SBOM generation is implemented;
10. canonical and translated documentation matches the promoted matrix.

Until these criteria are met, the correct public state remains pre-1.0 with explicit `experimental`/`unsupported` support declarations.

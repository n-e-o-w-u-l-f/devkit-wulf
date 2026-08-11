# devkit-wulf roadmap

Status date: **2026-08-11**

The roadmap distinguishes **implemented mechanics** from **promoted support**. No environment/platform combination is promoted merely because an installer path exists.

## Current implementation snapshot

The repository has moved beyond the initial generic bootstrap scaffold. System-native and verified-artifact contracts now exist for selected concrete environments, with dedicated validation and CI paths. These implementations remain subject to the support-promotion gates in `AGENTS.md`.

Implemented or materially advanced since the previous roadmap snapshot:

- Python 3.12 system-native routing for Linux, WSL, macOS and Windows;
- Go stable system-native routing for Linux, WSL and macOS plus a verified native Windows artifact route;
- Rust stable system-native routing for Linux, WSL and macOS plus a verified native Windows `rustup-init` artifact route;
- Flutter stable system-native routing for Linux, macOS and Windows, with WSL kept fail-closed where no verified route exists;
- native kubectl stable artifact contracts for Windows and macOS;
- dedicated manifest/schema validation, offline fixtures and CI workflows for the above routes;
- additional dedicated validation workflows covering installer families, .NET/Linux research contracts, PHP/Composer on Windows and JetBrains Toolbox.

## Phase 0 — orchestration foundation

### Implemented

- repository governance contract (`AGENTS.md`);
- GATE-00 through GATE-19 definitions;
- versioned environment manifest schema;
- platform catalog;
- environment catalog;
- host/architecture detection;
- support/strategy resolver;
- plan mode;
- state event log;
- remote-script inspection gate;
- verification framework;
- fail-closed uninstall framework;
- CI/security test definitions;
- installer-family catalog and system-native release-facing entrypoint model.

### Promotion blockers

- all required CI jobs must pass on their configured runners;
- rollback ownership needs product-specific implementation before individual uninstall promotion;
- package/version conflict detection must become richer for version-manager coexistence;
- release checksum/SBOM generation remains a release gate.

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
- system-native entrypoint routing for selected versioned environments.

### Still gated

- environment-by-environment support promotion from CI evidence;
- reboot/resume state for WSL feature activation;
- explicit WSL distribution post-install handoff;
- Windows PATH refresh after installers that modify environment variables outside the current process;
- broader real-host validation beyond CI-capable combinations.

## Phase 2 — Fedora/RHEL / openSUSE / Alpine

### Implemented

- host detection;
- `dnf`, `zypper`, `apk` package-manager adapters;
- distro-container CI definitions;
- platform/architecture catalog entries.

### Still gated

- real version matrix across Fedora/RHEL/Rocky/Alma;
- Leap/Tumbleweed target tests;
- musl-vs-glibc compatibility validation per environment on Alpine.

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

### Implemented mechanics

- package-manager strategies;
- WinGet strategies;
- reviewed official-script strategies;
- Python 3.12 system-native adapters across Linux, WSL, macOS and Windows;
- Go stable system-native adapters for Linux, WSL and macOS;
- Go stable verified native Windows artifact adapter;
- Rust stable system-native adapters for Linux, WSL and macOS;
- Rust stable verified native Windows `rustup-init` artifact adapter;
- dedicated contract validation and CI for these versioned routes.

### Still gated

- support-state promotion based on completed CI/real-host evidence;
- verified vendor-repository setup modules for remaining distribution-specific paths such as some .NET combinations;
- a generalized signed/verified archive engine where product-specific contracts do not yet exist;
- complete compiler/runtime smoke-test fixtures across the matrix;
- product-specific safe removal and ownership tracking.

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
- Apple/Xcode stack;
- Docker;
- Podman;
- kubectl;
- OpenTofu.

### Implemented mechanics

- Flutter stable system-native routing for Linux, macOS and Windows;
- managed Flutter verification and offline fixture coverage;
- explicit fail-closed WSL behavior for unsupported Flutter stable routes;
- native kubectl stable artifact contracts for Windows and macOS;
- verified kubectl helpers, offline fixtures, schema validation and CI;
- dedicated workflow/manifest work for PHP/Composer and JetBrains Toolbox.

### Still gated

- Android SDK component and emulator planner;
- Visual Studio workload/channel resolver;
- JetBrains product selection after Toolbox installation;
- Eclipse package-flavor selection;
- Docker Engine official repository adapters for each Linux family;
- Podman Machine lifecycle/state tracking;
- kubectl cluster-aware version resolver beyond the implemented native artifact contracts;
- OpenTofu vendor repository setup on Debian/RPM families;
- product-specific safe removal and complete ownership tracking for artifact installs.

## Phase 5 — BSD family

### Implemented

- detection for FreeBSD, OpenBSD, NetBSD and DragonFly BSD;
- bootstrap for available native package managers;
- catalog strategy entries;
- fail-closed experimental status.

### Promotion requirement

Each BSD/environment combination requires real or authoritative target validation. One BSD passing does not promote another.

## Phase 6 — illumos / Solaris / AIX

### Implemented

- host detection;
- bootstrap prerequisite paths that refuse unknown package ecosystems;
- source/target-only distinctions;
- Go cross-target separation;
- Temurin/source research evidence.

### Promotion requirement

These remain authoritative-target validation platforms. No support promotion occurs from POSIX compatibility, successful bootstrap, or cross-compilation capability alone.

# Repository/documentation completion targets

Before treating the repository itself as documentation-complete:

1. keep `CHANGELOG.md`, `ROADMAP.md` and the canonical README synchronized with merged implementation work;
2. ensure each executable environment/platform route has corresponding environment documentation and upstream-source evidence;
3. add repository topics/tags that reflect the actual project scope;
4. define and enforce a repository-wide license metadata strategy if REUSE compliance is adopted, without changing the current MIT license choice implicitly;
5. keep translations synchronized whenever the canonical README changes materially;
6. document release evidence, checksums and SBOM generation before the first stable release.

# Release criteria

Before the first stable release:

1. required CI runners execute and pass;
2. at least one environment in each claimed primary platform family passes install → verify → install again → verify;
3. support-state promotions are committed separately from adapter implementation;
4. integrity/signature gates are exercised by tests;
5. no critical security finding remains unresolved;
6. ownership-aware removal exists for any environment advertised as safely removable;
7. release checksum/SBOM generation is implemented;
8. release documentation and translations match the promoted support matrix.

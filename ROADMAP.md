# devkit-wulf roadmap

Status date: **2026-08-10**

The roadmap distinguishes **implemented mechanics** from **promoted support**. No environment/platform combination is promoted merely because an installer path exists.

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
- CI/security test definitions.

### Promotion blockers

- CI must execute successfully on the configured GitHub runners;
- rollback ownership needs product-specific implementation before individual uninstall promotion;
- package/version conflict detection must become richer for version-manager coexistence.

## Phase 1 — Windows / WSL2 / Debian / Ubuntu / Arch / macOS

### Implemented

- native Windows PowerShell orchestrator;
- WinGet adapter with installed-package detection;
- explicit WSL planning/bootstrap path;
- WSL distro discovery and no implicit WSL1 conversion;
- Linux distribution detector;
- apt/pacman adapters;
- macOS bootstrap with Xcode CLT check and gated Homebrew bootstrap;
- WSL filesystem guidance.

### Still gated

- environment-by-environment CI promotion;
- reboot/resume state for WSL feature activation;
- explicit WSL distribution post-install handoff;
- Windows PATH refresh after installers that modify environment variables outside the current process.

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

### Executable today when selected strategy is implemented

- package-manager strategies;
- WinGet strategies;
- reviewed official-script strategies.

### Still gated

- verified vendor-repository setup modules for environments such as distribution-specific .NET paths;
- generic signed/verified archive adapter;
- complete compiler smoke-test fixtures;
- product-specific safe removal.

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

### Still gated

- signed/verified archive download engine;
- Android SDK component and emulator planner;
- Flutter SDK archive/checksum/path ownership;
- Visual Studio workload/channel resolver;
- JetBrains product selection after Toolbox installation;
- Eclipse package-flavor selection;
- Docker Engine official repository adapters for each Linux family;
- Podman Machine lifecycle/state tracking;
- kubectl cluster-aware version resolver;
- OpenTofu vendor repository setup on Debian/RPM families.

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

# Release criteria

Before the first stable release:

1. required CI runners execute and pass;
2. at least one environment in each claimed primary platform family passes install → verify → install again → verify;
3. support-state promotions are committed separately from adapter implementation;
4. integrity/signature gates are exercised by tests;
5. no critical security finding remains unresolved;
6. ownership-aware removal exists for any environment advertised as safely removable;
7. release checksum/SBOM generation is implemented.

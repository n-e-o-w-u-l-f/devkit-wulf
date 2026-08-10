# ChatGPT Agent Directive — devkit-wulf Multi-Platform Developer Environment Installer

## 0. Mission

Develop and maintain `devkit-wulf` as a secure, idempotent, extensible multi-platform developer-environment installer.

The project SHALL detect the host operating system, distribution, architecture, available package managers and virtualization capabilities and install each selected developer environment using the safest and most appropriate supported installation path.

The project SHALL support native installation where appropriate and SHALL use WSL2, virtualization or containers only when they are technically justified or required.

Never claim support for an operating-system/environment combination that has not passed its required gates.

## 1. Core design principles

The implementation MUST separate:

1. host platform detection;
2. package-manager abstraction;
3. environment definitions;
4. installation strategy;
5. configuration;
6. verification;
7. rollback;
8. testing.

Environment definitions MUST NOT contain unnecessary distribution-specific logic. Platform adapters MUST NOT duplicate generic environment definitions.

Every environment/platform combination MUST have an explicit support state: `native`, `wsl2`, `vm`, `container`, `source`, `target-only`, `experimental`, or `unsupported`. Absence of an entry MUST be treated as `unsupported`.

## 2. Initial platform catalogue

Implement detection and adapters for at least:

- Windows 11, supported Windows 10 releases, supported Windows Server releases; x64 and ARM64.
- WSL2 distributions: Debian, Ubuntu, Arch Linux, openSUSE, Kali Linux. Detect the actual distribution independently of the Windows host and never assume `apt`.
- Linux: Debian, Ubuntu, Linux Mint, Kali Linux, Raspberry Pi OS, Arch Linux, Manjaro, Fedora, RHEL, Rocky Linux, AlmaLinux, openSUSE, Alpine Linux.
- Architectures: x86_64/amd64, arm64/aarch64, armv7 where supported, riscv64 where supported, ppc64le where supported, s390x where supported.
- macOS Intel and Apple Silicon.
- BSD: FreeBSD, OpenBSD, NetBSD, DragonFly BSD.
- Extended Unix: illumos, Oracle Solaris, AIX, but only for actually supported combinations.

Never emulate support merely because a POSIX shell exists.

## 3. Initial developer-environment catalogue

Create independent modules for at least:

- Base: Git, Git LFS, SSH, GPG, curl, wget where appropriate, archive utilities, compiler prerequisites, certificates, shell integration.
- Editors/IDEs: Visual Studio Code, Visual Studio / Build Tools, JetBrains Toolbox / supported IDEs, Eclipse, Android Studio, Xcode where applicable.
- C/C++: MSVC, Windows SDK, GCC, LLVM/Clang, Make, CMake, Ninja, debugger tooling.
- Python: Python, pip, venv, project-isolated environments; never destructively replace system Python.
- JavaScript/TypeScript: Node.js, npm, Corepack where applicable, Deno, Bun.
- JVM: OpenJDK/Eclipse Temurin, Maven, Gradle; permit side-by-side JDKs when supported.
- .NET: SDK and appropriate runtimes; Windows-specific workloads only on native Windows.
- Go: distinguish host support from GOOS/GOARCH cross-compilation targets.
- Rust: use official target tiers; distinguish host tools from compilation targets.
- PHP: CLI, headers where appropriate, Composer, extensions via platform-native mechanisms.
- Ruby: Ruby, RubyGems, Bundler; avoid overwriting system-managed Ruby.
- Mobile: Android Studio/SDK/platform-tools/build-tools/emulator only where supported; Flutter/Dart and host toolchains; Xcode/Swift/Apple SDKs only on macOS.
- Containers: Docker and Podman with native Linux engine vs Desktop/Machine/WSL2 backend explicitly distinguished.
- Infrastructure: kubectl and OpenTofu.

Additional infrastructure tools may be introduced only after current upstream platform and installation-security research.

## 4. Windows architecture

Windows SHALL have independent native and WSL2 environment domains.

Native Windows is preferred for Windows-specific development such as Visual Studio, MSVC, Windows SDK, native .NET, Windows GUI IDEs, Android Studio where supported, and Windows desktop development. Prefer WinGet where an appropriate trusted package exists.

For WSL2 Linux-first environments, the installer MUST detect WSL2 availability and installed distributions, allow selection of an existing distribution, optionally install a supported distribution after explicit planning, install inside that distribution, and keep Windows and WSL PATH configuration separate.

Recommended predefined profiles:

- `wsl-stable` — Debian-based
- `wsl-rolling` — Arch-based

Do not silently create WSL distributions or convert WSL1 to WSL2. These operations require explicit plan and privilege gates.

## 5. Installation strategy precedence

Unless official upstream documentation explicitly recommends otherwise, prefer:

1. platform-native trusted package manager;
2. official vendor repository;
3. official signed installer/package;
4. verified upstream archive/binary;
5. verified source build;
6. containerized environment;
7. VM/WSL compatibility environment.

Never use arbitrary third-party install scripts merely because they are convenient. Any `curl | sh`, `curl | bash`, `irm | iex`, or equivalent execution MUST pass the remote-script gate. Prefer download, validation and inspection before execution.

## 6. Mandatory gates

### GATE-00 — Repository governance
Before changing repository content read `AGENTS.md`, repository documentation, applicable scope, existing conventions, tests, and current state. Do not overwrite unrelated user changes.

### GATE-01 — Host discovery
Detect OS, OS version, distribution/version, architecture, kernel, shell, package manager, privilege state, available disk space, WSL state where applicable, and virtualization capability where required. Failure to identify the host reliably blocks installation.

### GATE-02 — Support matrix
Resolve `environment × host × architecture × version` to one explicit support state. `unsupported` terminates the path. `experimental` requires explicit selection.

### GATE-03 — Version compatibility
Resolve requested/stable/LTS versions, host/architecture/dependency compatibility. Never silently substitute an incompatible newer major version.

### GATE-04 — Source trust
Every downloaded executable, script, archive or package must have a known official/trusted source. Record source URL and package identity. Never silently substitute third-party mirrors.

### GATE-05 — Integrity/signature
Where upstream provides checksums, GPG, Authenticode, Apple signing, repository/package signatures or Sigstore/cosign, validate them. Mismatch hard-fails. No silent `--skip-verify` fallback.

### GATE-06 — Remote script
Before execution: download; require HTTPS; identify official provenance; verify available integrity metadata; scan destructive commands, unexpected privilege escalation and persistence changes; log the artifact; execute only after checks pass. Avoid direct pipe-to-shell.

### GATE-07 — Privilege
Determine Administrator/elevated PowerShell/sudo/root needs and use least privilege. Do not run an entire module elevated because one step requires it.

### GATE-08 — Conflict
Detect existing installation/version/source/PATH/version managers/environment variables/incompatible system packages. Never destructively replace without a deliberate migration plan.

### GATE-09 — Plan/dry-run
Every installer must support plan mode showing detected platform, selected strategy, packages, repositories, downloads, PATH/environment changes, privilege requirements, disk impact when available, and verification commands. Plan mode makes no persistent changes.

### GATE-10 — State/rollback
Record packages, repositories, files, PATH/environment changes, and services changed by devkit-wulf. Do not promise rollback for changes that cannot safely be reversed.

### GATE-11 — Installation
Only after Gates 01–10 pass. Commands fail on errors, propagate status, expose stderr, avoid unexpected interaction, and avoid unrelated OS upgrades.

### GATE-12 — Verification
Prove functionality: executable resolution, version command, runtime/compiler/package manager/SDK smoke tests as appropriate. Package-manager exit code alone is insufficient.

### GATE-13 — PATH isolation
Prevent duplicate/destructive PATH changes, Windows/WSL leakage, system-binary replacement and incorrect precedence. PATH changes must be idempotent.

### GATE-14 — Idempotency
`install → verify → install again → verify` must not duplicate repositories/PATH/configuration or corrupt the environment.

### GATE-15 — Uninstall
Where safe provide `devkit-wulf remove <environment>`. Remove only owned/explicitly installed resources and never blindly remove shared dependencies.

### GATE-16 — Cross-platform CI
Test supported CI-capable Windows, Debian/Ubuntu, Arch where feasible, Fedora and macOS. Use containers for Linux adapters where appropriate and real/authoritative target systems for Extended Unix before promotion.

### GATE-17 — Security
Before merge run shell/static analysis, PowerShell analysis, secret/dependency scans, provenance checks and dangerous-command scans. Destructive filesystem/disk/registry/package operations and verification bypasses require explicit review.

### GATE-18 — Documentation
Each environment documents hosts, architectures, strategy, components, configuration, verification, uninstall behavior, limitations and upstream sources. Support claims must match tested support.

### GATE-19 — Release
Release is blocked unless required CI passes, manifests validate, no unresolved critical security issue exists, version/CHANGELOG are consistent, checksums exist and release artifacts are reproducible where practical. Produce an SBOM where feasible.

## 7. Manifest-driven architecture

Create machine-readable environment manifests. The schema SHALL be versioned and validated with JSON Schema or an equivalent schema system. Host support and cross-compilation support MUST be modeled separately.

## 8. CLI target

Design toward:

```text
devkit-wulf detect
devkit-wulf list
devkit-wulf list --supported
devkit-wulf list --platform windows
devkit-wulf plan <environment>
devkit-wulf install <environment>
devkit-wulf verify <environment>
devkit-wulf remove <environment>
devkit-wulf install profile:<name>
devkit-wulf install <environment> --target native|wsl:<distro>
devkit-wulf install <environment> --version <version>
devkit-wulf doctor
```

`doctor` SHALL detect broken PATHs, missing dependencies, conflicting installations and failed environment verification.

## 9. Profiles

Provide composable profiles: `minimal`, `web`, `backend`, `systems`, `mobile`, `devops`, `full`. `full` MUST NOT install unsupported or experimental environments automatically.

## 10. Windows/WSL filesystem policy

When Linux tools run inside WSL2, recommend Linux-side project storage. When native Windows tools run, recommend Windows-side storage. Do not relocate repositories or rewrite existing Git working directories automatically.

## 11. Research requirement

Before implementing or modifying an environment installer, research current official upstream documentation for releases, supported OS/architectures, installation commands, checksums/signing, package identifiers and EOL status. Prefer primary sources and record research date plus references in environment metadata.

## 12. Unsupported environments

Never force unsupported installs, blindly patch binaries, disable security checks, masquerade another OS, or mark cross-compilation as native host support. Report why unsupported and whether WSL2, VM, container, source or target-only alternatives exist.

## 13. Definition of Done

A combination may be marked supported only when detection, dependency resolution, installation, integrity verification, PATH/configuration, smoke tests, idempotency, removal behavior, documentation and required CI/target validation all pass. Until then use `experimental`, `target-only` or `unsupported`.

## 14. Initial implementation order

- Phase 0: contracts, manifest schema, detector, logging, state model, gate framework.
- Phase 1: Windows, WSL2, Debian/Ubuntu, Arch Linux, macOS.
- Phase 2: Fedora/RHEL, openSUSE, Alpine.
- Phase 3: Base, C/C++, Python, Node.js, Java, .NET, Go, Rust.
- Phase 4: Deno, Bun, PHP, Ruby, Android, Flutter, containers, kubectl, OpenTofu.
- Phase 5: BSD family.
- Phase 6: illumos, Solaris, AIX.

Do not allow later platform support to weaken security or correctness requirements.

## 15. Final constraint

`devkit-wulf` is an environment orchestrator, not a collection of unrelated bootstrap scripts. Prefer deterministic behavior, explicit support matrices, native platform mechanisms, verified upstream artifacts, minimal privilege, idempotency, testability, rollback awareness and modularity over maximizing nominal platform count.

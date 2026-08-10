# Platform and environment strategy

Research baseline: **2026-08-10**

This document defines the preferred development setup for each host family. It is a strategy document, not a claim that every catalog entry has already passed its support gates.

## Global selection rule

Choose the execution domain before choosing an installer:

1. Use **native host tooling** when the workload targets the host OS or upstream explicitly supports the host.
2. On Windows, use **WSL2** for Linux-first development where Linux filesystem semantics, native Linux packages, containers or reproducible Linux CI parity matter more than Windows-native integration.
3. Use a **container** for disposable/reproducible build environments, not as a substitute for IDE/SDK host integration that requires native GUI/device access.
4. Use a **VM** only where upstream requires another kernel/OS or where the host cannot safely provide the environment natively.
5. Use **source builds** only when there is no trustworthy native/vendor package path and the resulting ownership/update contract is explicit.

The fallback order remains:

`native package manager → official vendor repository → signed vendor package → verified archive → verified source build → container → VM/WSL compatibility domain`

## Windows 11 / serviced Windows 10 clients

### Native domain — preferred for

- Visual Studio, MSVC and Windows SDK;
- native .NET development;
- Windows desktop applications;
- VS Code desktop client;
- JetBrains/Eclipse desktop IDEs when their current Windows requirements are met;
- Android Studio on supported x86-64 Windows hosts;
- Docker Desktop / Podman client integration where their virtualization requirements are met;
- Flutter when Windows desktop is a target.

### WSL2 domain — preferred for

- Linux server/backend development;
- Linux package-manager parity with production;
- GCC/Clang Linux builds;
- Linux-native Python/Node/Go/Rust/JVM workflows;
- shell tooling that assumes Linux filesystem semantics;
- container workflows whose primary target is Linux.

### WSL policy

- The selected distribution is detected independently from Windows.
- `wsl-stable` prefers Debian.
- `wsl-rolling` prefers Arch Linux.
- Distribution creation is explicit.
- WSL1-to-WSL2 conversion is explicit and never automatic.
- Linux-tool projects should normally live in the WSL filesystem.
- Native Windows projects should normally remain on the Windows filesystem.
- Windows PATH and WSL PATH changes are independent state domains.

### Windows Server

Do not infer desktop-product support from Windows client support. In particular, current upstream documentation excludes VS Code Desktop and Docker Desktop from Windows Server. Server workloads require separate, product-specific paths.

## Debian / Ubuntu / Mint / Kali / Raspberry Pi OS

Preferred order:

1. `apt` packages for host-integrated tooling;
2. official vendor APT repositories for products whose distribution packages are unsuitable/outdated;
3. verified vendor archives where upstream does not provide a repository;
4. user-local version managers only through a separately reviewed strategy.

Do not replace distribution-owned Python/Ruby toolchains destructively. Use project virtual environments or explicit user-local version managers for project version isolation.

## Arch Linux / Manjaro

Preferred order:

1. official `pacman` repositories;
2. official upstream artifact/repository;
3. AUR only as a separately classified third-party strategy, never as an implicit trusted-vendor path.

`devkit-wulf` does not currently treat arbitrary AUR packages as equivalent to official upstream packages.

## Fedora / RHEL / Rocky / AlmaLinux

Preferred order:

1. `dnf` packages where they meet workload requirements;
2. official vendor RPM repositories;
3. verified upstream archives.

RHEL-family support is version-sensitive. A package name available on Fedora must not be assumed to exist unchanged on RHEL/Rocky/Alma.

## openSUSE

Prefer `zypper` and authoritative openSUSE/vendor repositories. Leap and Tumbleweed are detected separately at the platform level even where an environment currently shares the same strategy entry.

## Alpine Linux

Prefer `apk` and musl-compatible upstream artifacts. Never substitute a glibc-only Linux binary silently. Environments whose upstream Linux binary requires glibc must remain unsupported/experimental until a valid musl strategy exists.

## macOS

Preferred base:

1. Xcode Command Line Tools;
2. full Xcode when Apple platform development is requested;
3. Homebrew for generic developer tooling where appropriate;
4. signed/verified vendor applications or archives for IDEs/SDKs.

Homebrew is not silently installed. If the bootstrap is explicitly authorized to obtain Homebrew, it downloads the official installer first and applies the remote-script gate before execution.

Apple SDK/iOS/macOS development remains a native macOS-only environment.

## BSD family

FreeBSD, OpenBSD, NetBSD and DragonFly BSD use their native package ecosystems where suitable. They remain validation-tier platforms until real/authoritative target tests clear the Definition of Done.

Do not generalize one BSD's package names, libc behavior or architecture coverage to another BSD.

## illumos / Solaris / AIX

These are authoritative-target validation platforms.

- A POSIX shell is not proof of environment support.
- Go compilation targets are represented separately from host support.
- Temurin/JDK archives may exist for selected AIX/Solaris combinations, but exact release/architecture availability is checked per release.
- Source builds require product-specific dependency and verification contracts.

No Extended Unix environment is promoted solely because bootstrap prerequisites installed successfully.

# Environment-specific optimal strategies

## C / C++

- Windows native target: Visual Studio/MSVC + Windows SDK; LLVM/CMake/Ninja may coexist.
- Linux: distro GCC/Clang + CMake/Ninja + debugger.
- macOS: Apple Clang/Xcode CLT; optional Homebrew GCC/LLVM only when required.
- WSL2: use Linux compilers inside WSL; do not point a Linux build at Windows-native compiler binaries.

## Python

- Keep OS Python ownership intact.
- Use `venv` for project dependencies.
- Add version-manager support as a distinct future strategy when multiple interpreter versions are required.

## Node.js

- System package path is suitable for simple host tooling.
- Project teams needing multiple Node release lines should use a separately gated version-manager strategy rather than an unreviewed remote install script.

## Deno / Bun / Rust

Their official bootstrap scripts are represented but never treated as pipe-to-shell exceptions. The script must be downloaded over HTTPS, recorded, scanned and explicitly accepted before execution.

## Java

Use a current supported JDK (Temurin or distribution OpenJDK as appropriate). Maven/Gradle remain separate build tools even if IDEs bundle integrations. Side-by-side JDKs should be handled explicitly rather than overwriting `JAVA_HOME` blindly.

## .NET

- Windows: native Microsoft SDK packages are preferred.
- Linux: use the distribution/vendor path documented for the specific distribution/version.
- macOS: Microsoft-supported package/archive path.
- Windows-only workloads stay on native Windows.

## Go

Host installation and `GOOS/GOARCH` target capability are distinct. A target tuple in the manifest never makes that OS a supported devkit-wulf host.

## IDEs

- VS Code + WSL: Windows VS Code client, VS Code Server inside WSL.
- Visual Studio: Windows-native only.
- JetBrains Toolbox: use only on currently documented Windows/macOS/Linux combinations and treat individual IDE requirements separately.
- Eclipse: select the desired package flavor explicitly; do not assume Java, C/C++, PHP and modeling users want the same bundle.

## Android

Current upstream requirements are intentionally restrictive in the manifest:

- Windows host: x86-64, not Windows ARM.
- Linux host: x86-64/glibc, not Linux ARM.
- macOS: Intel/Apple Silicon packages exist, with Intel support being phased out upstream.

Android emulator installation additionally requires a virtualization/resource gate.

## Flutter

The SDK is multi-host, but desktop/mobile target capability is host-bound. Windows desktop requires Windows, Linux desktop requires Linux, and macOS/iOS development requires macOS.

## Docker

- Linux: prefer native Docker Engine for a native Linux engine requirement.
- Docker Desktop for Linux is VM-backed and is modeled separately from native Engine semantics.
- Windows: Desktop commonly uses WSL2/Hyper-V; Windows Server requires a separate server/container path.
- macOS: Docker Desktop is VM-backed.

## Podman

- Linux: native engine.
- Windows/macOS: `podman machine` provides the required Linux VM.

## kubectl

Select the client version in relation to the target cluster. The newest client is not automatically optimal; Kubernetes supports a defined version-skew window.

## OpenTofu

Prefer official package repositories/package-manager integrations where available. Standalone installation must retain upstream checksum/signature verification; verification bypass flags are not permitted as automatic fallbacks.

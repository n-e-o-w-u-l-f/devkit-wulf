# Upstream research baseline

Research date: **2026-08-10**

This file records primary upstream documentation used to seed the manifest. It is evidence, not a permanent guarantee: version-sensitive entries must be revalidated before changing installers or support claims.

## Windows / WSL

- Microsoft WSL install: https://learn.microsoft.com/windows/wsl/install
- Microsoft WSL development environment: https://learn.microsoft.com/windows/wsl/setup/environment
- Microsoft WSL version comparison: https://learn.microsoft.com/windows/wsl/compare-versions
- Microsoft WSL commands: https://learn.microsoft.com/windows/wsl/basic-commands

Key findings:

- Current `wsl --install` flow targets Windows 10 version 2004/build 19041+ or Windows 11; older supported WSL2 scenarios have separate manual requirements.
- WSL distributions must be detected independently; Microsoft documents Debian, Ubuntu, Kali, openSUSE and Arch Linux among available/importable distributions.
- WSL2 project files should normally live on the same OS filesystem as the tools operating on them to avoid cross-filesystem performance penalties.

## VS Code

- Requirements: https://code.visualstudio.com/docs/supporting/requirements
- WSL development: https://code.visualstudio.com/docs/remote/wsl

Key findings:

- Desktop VS Code supports serviced 64-bit Windows clients, supported macOS releases and documented Debian/Red-Hat Linux baselines.
- Windows Server is not a supported VS Code desktop platform.
- WSL usage is a Windows client + VS Code Server in WSL model; do not install a second full Linux GUI VS Code instance merely to use WSL.

## Python

- Python documentation: https://docs.python.org/3/using/index.html
- macOS installation: https://docs.python.org/3/using/mac.html
- Windows installation: https://docs.python.org/3/using/windows.html

Policy:

- Never replace a distribution-owned system Python destructively.
- Prefer OS packages for system integration or a user/project isolation mechanism for application development.

## Node.js

- Downloads/releases: https://nodejs.org/en/download
- Release information: https://nodejs.org/en/about/previous-releases

Key findings:

- Node publishes LTS and Current release lines with signed checksum material.
- Version managers may be suitable for user-local development, but direct remote-script execution must still pass GATE-06.

## Go

- Source/platform documentation: https://go.dev/doc/install/source
- Binary installation: https://go.dev/doc/install

Key findings:

- Go targets include AIX, Android, DragonFly BSD, FreeBSD, illumos, Linux, Darwin/iOS, NetBSD, OpenBSD, Plan 9, Solaris and Windows in specific architecture combinations.
- A cross-compilation target is not automatically a supported development host.

## Rust

- Platform support: https://doc.rust-lang.org/rustc/platform-support.html
- Target tier policy: https://doc.rust-lang.org/rustc/target-tier-policy.html
- rustup: https://rustup.rs/

Key findings:

- Rust support guarantees are explicitly tiered.
- Host tools and compilation-only targets must be represented separately.

## .NET

- Install overview: https://learn.microsoft.com/dotnet/core/install/
- Windows: https://learn.microsoft.com/dotnet/core/install/windows
- Linux: https://learn.microsoft.com/dotnet/core/install/linux
- macOS: https://learn.microsoft.com/dotnet/core/install/macos
- install scripts: https://learn.microsoft.com/dotnet/core/tools/dotnet-install-script

Key findings:

- Current Microsoft documentation covers Windows, macOS and selected Linux distributions.
- Linux package sources differ by distribution: some packages are Microsoft-provided and others distribution-maintained.
- The install script supports Linux/macOS and Windows but is not treated as a pipe-to-shell exception.

## Java / Eclipse Temurin

- Installation overview: https://adoptium.net/installation/
- Archive installation: https://adoptium.net/installation/archives/

Key findings:

- Temurin provides platform-specific packages/archives and SHA-256 checksum material.
- Archive verification documentation explicitly covers Linux, macOS, AIX, Solaris and Windows.
- Exact JDK/architecture availability must be queried/revalidated per release rather than inferred globally.

## Android Studio / Android SDK

- Installation/system requirements: https://developer.android.com/studio/install
- Downloads/checksums: https://developer.android.com/studio

Key findings as of 2026-08-10:

- Windows Android Studio requires 64-bit Windows and ARM-based Windows CPUs are currently not supported.
- Linux Android Studio currently requires x86_64/glibc; ARM-based Linux CPUs are currently not supported.
- macOS packages exist for Intel and Apple Silicon, while Android documentation notes Intel Mac support is being phased out.
- Google publishes SHA-256 values for Android Studio and command-line-tools downloads.

## Flutter

- Manual installation: https://docs.flutter.dev/install/manual
- SDK archive: https://docs.flutter.dev/install/archive
- Host/target setup: https://docs.flutter.dev/install/custom
- PATH configuration: https://docs.flutter.dev/install/add-to-path

Key findings:

- Flutter SDK bundles are provided for Windows, macOS and Linux.
- Target platforms are host constrained: Windows desktop on Windows, macOS/iOS on macOS, Linux desktop on Linux; web is broadly available.

## Docker

- Windows Desktop: https://docs.docker.com/desktop/setup/install/windows-install/
- macOS Desktop: https://docs.docker.com/desktop/setup/install/mac-install/
- Linux Desktop: https://docs.docker.com/desktop/setup/install/linux/

Key findings:

- Docker Desktop on Windows normally uses a WSL2 or Hyper-V backend; per-user mode recommends WSL2 for most users.
- Docker Desktop is not supported on Windows Server; Windows Server container setup must use Microsoft/server-specific mechanisms instead.
- Docker Desktop for Linux itself runs a VM and must not be represented as the native Linux Docker Engine.
- Docker Desktop licensing terms must not be hidden by the installer.

## Podman

- Podman machine: https://docs.podman.io/en/latest/markdown/podman-machine.1.html

Key finding:

- Podman is Linux-native; macOS and Windows require a managed Linux virtual machine through `podman machine`.

## OpenTofu

- Installation overview: https://opentofu.org/docs/intro/install/
- Windows: https://opentofu.org/docs/intro/install/windows/
- Debian: https://opentofu.org/docs/intro/install/deb/
- RPM distributions: https://opentofu.org/docs/intro/install/rpm/
- Standalone verification: https://opentofu.org/docs/intro/install/standalone/

Key findings:

- Official installation paths exist for Windows, macOS, major Linux packaging families, FreeBSD/standalone and OCI use.
- Official standalone instructions include checksum/signature verification and explicitly tell users to inspect the installer script.
- `--skip-verify` is not an acceptable automatic fallback in devkit-wulf.

## Research promotion rule

An environment/platform entry may move from `experimental` to a supported state only after:

1. upstream platform support is current;
2. architecture compatibility is current;
3. installation source/provenance is recorded;
4. required integrity/signature behavior is implemented;
5. host smoke tests and idempotency tests pass;
6. uninstall ownership behavior is known;
7. the relevant CI or authoritative target-system gate passes.

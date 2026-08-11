# devkit-wulf

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Polski](README.pl.md) | [简体中文](README.cn.md) | [Русский](README.ru.md) | [Español](README.es.md)

Secure, manifest-driven multi-platform developer environment bootstrapper and orchestrator for Windows, WSL2, Linux, macOS, BSD and explicitly researched extended Unix targets.

> **Status:** pre-1.0 bootstrap. Platform/environment combinations remain `experimental` until their required CI and target-system gates pass. The repository intentionally does not advertise unverified combinations as supported.

For the audited implementation/support boundary as of **2026-08-11**, see [`docs/REPOSITORY-STATUS.md`](docs/REPOSITORY-STATUS.md).

## Design

`devkit-wulf` separates:

- host and architecture detection;
- package-manager/source selection;
- environment metadata and support policy;
- installation strategy;
- non-mutating planning;
- mutation and privilege handling;
- integrity verification;
- runtime/environment verification;
- state tracking and ownership awareness;
- CI/security/release gates.

Support status and execution strategy are modeled independently. A combination may therefore be `support: experimental` while using `strategy: package-manager`, `winget`, `official-script`, `official-archive`, `source`, `vm`, `container`, `wsl2`, or `xcode`.

Release-facing installer entrypoints are **system-native**. `devkit-wulf` does not publish one universal executable and claim that the same binary can run on Windows, Debian, Fedora, macOS, BSD and extended Unix. Shared environment contracts describe what should exist; system-specific adapters describe how that environment is installed in a particular execution domain. See [`docs/installer-architecture.md`](docs/installer-architecture.md).

## Quick start

### Native Linux

```sh
./bootstrap/linux.sh

./installers/linux/devkit-wulf.sh detect
./installers/linux/devkit-wulf.sh list
./installers/linux/devkit-wulf.sh plan python
./installers/linux/devkit-wulf.sh install python --experimental
./installers/linux/devkit-wulf.sh verify python
./installers/linux/devkit-wulf.sh doctor
```

The native Linux entrypoint rejects WSL so host/domain selection is explicit.

### macOS

```sh
./bootstrap/macos.sh
./installers/macos/devkit-wulf.sh detect
./installers/macos/devkit-wulf.sh plan python
```

### BSD / Solaris / illumos / AIX

```sh
./bootstrap/bsd.sh
./installers/bsd/devkit-wulf.sh detect

./bootstrap/solaris.sh
./installers/solaris/devkit-wulf.sh detect

./bootstrap/aix.sh
./installers/aix/devkit-wulf.sh detect
```

Bootstraps install only the small parser/tooling prerequisites needed by the orchestrator and do not install developer profiles. Bootstrap success is not environment-support promotion.

### Windows PowerShell

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\bootstrap\windows.ps1
.\installers\windows\devkit-wulf.ps1 detect
.\installers\windows\devkit-wulf.ps1 list
.\installers\windows\devkit-wulf.ps1 plan python
.\installers\windows\devkit-wulf.ps1 install python -Experimental
.\installers\windows\devkit-wulf.ps1 verify python
.\installers\windows\devkit-wulf.ps1 doctor
```

Windows PowerShell 5.1 and PowerShell 7 are accepted by the native orchestrator. WinGet-backed installs are checked before mutation so already-installed exact package IDs are not deliberately reinstalled.

A future Windows `.exe`/`.msi` release is a Windows-specific artifact. It is not a Linux installer.

### WSL2

Run the WSL entrypoint inside the selected WSL distribution:

```sh
./bootstrap/linux.sh
./installers/wsl/devkit-wulf.sh detect
./installers/wsl/devkit-wulf.sh plan python
```

WSL distributions are detected independently from the Windows host. `devkit-wulf` never silently creates a WSL distribution or converts WSL1 to WSL2.

To inspect a Windows-side WSL change before allowing it:

```powershell
.\bootstrap\windows.ps1 -PlanWSL2 -Distribution Debian
```

A WSL feature/distribution mutation additionally requires an elevated shell and `-AllowSystemChange`.

Store Linux-tool projects in the Linux filesystem when working inside WSL2. Keep native-Windows projects on the Windows side; cross-filesystem I/O is intentionally not treated as the default layout.

## Commands

Generic catalog orchestration:

```text
devkit-wulf detect
devkit-wulf list
devkit-wulf list --supported
devkit-wulf list --platform <platform>
devkit-wulf plan <environment>
devkit-wulf install <environment> [--experimental]
devkit-wulf verify <environment>
devkit-wulf remove <environment>
devkit-wulf install profile:<name> [--experimental]
devkit-wulf doctor
```

Native Windows uses the equivalent PowerShell switches such as `-Experimental` and `-AcceptRemoteScript`.

`plan` is non-mutating. `install` refuses unsupported combinations and requires explicit opt-in for experimental combinations. Strategies that lack a reviewed dedicated adapter fail closed instead of guessing an installer.

The generic CLI roadmap still includes explicit `--version` and `--target native|wsl:<distro>` resolution; those capabilities are not yet implemented in the generic cores and remain tracked by issue #4.

## Versioned system-native selectors

Versioned selectors are routed at the release-facing `installers/` boundary, not absorbed into the generic cores.

Audit state on **2026-08-11**:

| Selector | Linux | WSL2 | macOS | Windows |
| --- | --- | --- | --- | --- |
| `python@3.12` | experimental route | experimental route | experimental route | experimental route |
| `go@stable` | experimental route | experimental route | experimental route | experimental route |
| `rust@stable` | experimental route | experimental route | experimental route | staged adapter; central route gated |
| `flutter@stable` | experimental route | unsupported | experimental route | experimental route (amd64) |
| `kubectl@stable` | not centrally routed | not centrally routed | direct native adapter exists | direct native adapter exists |

This table describes **routing/implementation**, not promoted support. Windows Go still has an obsolete CI fail-closed assertion tracked by issue #35. Windows Rust intentionally demonstrates the opposite state: native adapter/manifest/test work exists, but the top-level release selector remains gated.

## Initial environments

### Core and languages

- `base`
- `cpp`
- `python`
- `node`
- `deno`
- `bun`
- `java`
- `dotnet`
- `go`
- `rust`
- `php`
- `ruby`

### Editors and IDEs

- `vscode`
- `visualstudio`
- `jetbrains`
- `eclipse`

### Mobile / platform SDKs

- `android`
- `flutter`
- `xcode`

### Containers / infrastructure

- `docker`
- `podman`
- `kubectl`
- `opentofu`

> **Known contract drift:** `profiles/profiles.json` and `tests/validate_manifests.py` still reference the previous `apple` ID while the canonical environment catalog uses `xcode`. This is tracked by issue #34; the README follows the canonical catalog ID.

## Profiles

- `minimal`
- `web`
- `backend`
- `systems`
- `mobile`
- `devops`
- `full`
- `wsl-stable`
- `wsl-rolling`

The `full` profile never opts into experimental environments by itself. Unsupported and target-only entries are never converted into host installations. Profiles referencing an unknown environment ID must fail validation rather than silently remap it.

## Platform model

Primary implementation targets include:

- Windows 11 and serviced Windows 10 clients, x64/ARM64 where the individual environment contract supports it;
- WSL2 with explicitly catalogued Linux distributions;
- Debian/Ubuntu/Mint/Kali/Raspberry Pi OS;
- Arch/Manjaro;
- Fedora/RHEL/Rocky/Alma;
- openSUSE;
- Alpine;
- macOS Intel and Apple Silicon.

Research/validation targets include:

- FreeBSD, OpenBSD, NetBSD, DragonFly BSD;
- illumos, Oracle Solaris, AIX.

Extended Unix entries remain experimental or target-only until validated on authoritative target systems. Cross-compilation capability is represented separately from host support.

## Security model

The implementation follows the gates in [`AGENTS.md`](AGENTS.md). In particular:

- no silent unsupported fallback;
- no automatic `curl | sh` / `irm | iex` execution;
- source provenance is recorded in manifests;
- package-manager and official-vendor mechanisms are preferred where appropriate;
- remote scripts must be reviewed/gated before execution;
- checksum/signature mismatches are hard failures where reviewed upstream integrity metadata is available;
- privilege escalation is scoped to operations that require it;
- `plan` never mutates the host;
- reviewed artifact transactions stage before mutation and refuse unsafe archive paths;
- foreign/unowned managed destinations fail closed;
- persistent PATH mutation is not implicit in reviewed user-local artifact adapters;
- destructive uninstall is refused where ownership cannot be established safely;
- Windows Server exclusions are evaluated independently from Windows client support where upstream requires it;
- release artifact formats are bound to explicit installer families rather than treated as cross-OS executables.

Safe removal is not complete merely because ownership markers exist. Product-specific removal/rollback remains an open gate under issue #3.

## Repository layout

```text
AGENTS.md               governance contract and mandatory gates
installers/             release-facing system-native entrypoints and adapters
environments/           shared version-specific environment intent
bin/                    internal POSIX and PowerShell orchestration cores during migration
bootstrap/              minimal host bootstrap scripts
manifests/              platform/environment/artifact/repository/installer-family contracts
profiles/               composable environment selections
research/               dated upstream support/source research
scripts/                validation/security helpers
tests/                  semantic validators and offline adapter/CLI fixtures
.github/workflows/       CI gates
```

The installer-family contract lives in [`manifests/installer-families.json`](manifests/installer-families.json). Current system entrypoints and routing are listed in [`installers/README.md`](installers/README.md).

## Current automation boundary

Package-manager and selected verified repository/artifact/script strategies have executable adapters. Product-specific `manual`, source-build, VM, container, and not-yet-integrated strategies intentionally fail closed until their source, integrity, ownership, PATH, verification, idempotency, and removal contracts are complete.

The `installers/` tree is the release-facing boundary. Existing code under `bin/` and `lib/` is migrated incrementally so working security gates are not weakened merely to achieve a cosmetic directory move.

Direct adapter existence, shared-selector routing, and support promotion are deliberately different states.

## Validation and release state

The repository contains extensive offline Shell/PowerShell fixtures and Python semantic validators. However, the latest audited GitHub Actions execution was blocked **before runner start** by an external account/billing condition, so hosted CI is not currently authoritative evidence of pass or product-test failure.

There are currently no GitHub Releases and no Git tags. Stable release checksums/SBOM remain an open release gate under issue #6.

See [`docs/REPOSITORY-STATUS.md`](docs/REPOSITORY-STATUS.md) for the complete audited current/desired state and known static inconsistencies.

## Upstream research

The broad support/source baseline was refreshed on **2026-08-10**, with product-specific contracts updated on **2026-08-11** where implementation research advanced. See [`research/upstream-sources.md`](research/upstream-sources.md) and the individual dated manifests/contracts. Runtime versions and EOL information are not assumed permanent and must be revalidated before version-sensitive changes.

For host/domain strategy, see [`docs/platform-strategy.md`](docs/platform-strategy.md). For installer/runtime separation, see [`docs/installer-architecture.md`](docs/installer-architecture.md). The phased implementation/promotion state is tracked in [`ROADMAP.md`](ROADMAP.md).

## Documentation and community

- [Audited repository status](docs/REPOSITORY-STATUS.md)
- [Contributing guide](CONTRIBUTING.md)
- [Support and issue-reporting guide](SUPPORT.md)
- [Security policy](SECURITY.md)
- [Installer architecture](docs/installer-architecture.md)
- [Translation policy](docs/TRANSLATIONS.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)

## Support the project

If `devkit-wulf` is useful to you, you can support its continued development through PayPal:

<a href="https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U" target="_blank"><img src="https://www.paypalobjects.com/en_US/DK/i/btn/btn_donateCC_LG.gif" alt="Donate with PayPal" title="PayPal - The safer, easier way to pay online!" /></a>

[Donate with PayPal](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

Scan or click the QR code to open the same PayPal donation page:

[![PayPal donation QR code](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

## License

MIT — see [`LICENSE`](LICENSE).

# devkit-wulf

Secure, manifest-driven multi-platform developer environment bootstrapper and orchestrator for Windows, WSL2, Linux, macOS, BSD and explicitly researched extended Unix targets.

> **Status:** pre-1.0 bootstrap. Platform/environment combinations remain `experimental` until their required CI or target-system gates pass. The repository intentionally does not advertise unverified combinations as supported.

## Design

`devkit-wulf` separates the responsibilities of:

- host and architecture detection;
- package-manager selection;
- environment metadata and support policy;
- installation strategy;
- non-mutating planning;
- mutation and privilege handling;
- verification;
- state tracking and rollback awareness;
- CI/security gates.

Support status and execution strategy are modeled independently. A combination may therefore be `support: experimental` while using `strategy: package-manager`, `winget`, `official-script`, `official-archive`, `source`, `vm`, `container`, `wsl2`, or `xcode`.

## Quick start

### Linux / macOS / BSD / Unix

```sh
./bootstrap/linux.sh        # Linux / WSL2
./bootstrap/macos.sh        # macOS
./bootstrap/bsd.sh          # FreeBSD/OpenBSD/NetBSD/DragonFly
./bootstrap/solaris.sh      # Solaris/illumos
./bootstrap/aix.sh          # AIX

./bin/devkit-wulf detect
./bin/devkit-wulf list
./bin/devkit-wulf plan python
./bin/devkit-wulf install python --experimental
./bin/devkit-wulf verify python
./bin/devkit-wulf doctor
```

Bootstraps install only the small parser/tooling prerequisites needed by the orchestrator and do not install developer profiles.

### Windows PowerShell

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\bootstrap\windows.ps1
.\bin\devkit-wulf.ps1 detect
.\bin\devkit-wulf.ps1 list
.\bin\devkit-wulf.ps1 plan python
.\bin\devkit-wulf.ps1 install python -Experimental
.\bin\devkit-wulf.ps1 verify python
.\bin\devkit-wulf.ps1 doctor
```

Windows PowerShell 5.1 and PowerShell 7 are accepted by the native orchestrator. WinGet-backed installs are checked before mutation so already-installed exact package IDs are not deliberately reinstalled.

### WSL2

Run the Linux CLI inside the selected WSL distribution. WSL distributions are detected independently from the Windows host. `devkit-wulf` never silently creates a WSL distribution or converts WSL1 to WSL2.

To inspect a Windows-side WSL change before allowing it:

```powershell
.\bootstrap\windows.ps1 -PlanWSL2 -Distribution Debian
```

A WSL feature/distribution mutation additionally requires an elevated shell and `-AllowSystemChange`.

Store Linux-tool projects in the Linux filesystem when working inside WSL2. Keep native-Windows projects on the Windows side; cross-filesystem I/O is intentionally not treated as the default layout.

## Commands

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

Native Windows uses the equivalent PowerShell switches `-Experimental` and `-AcceptRemoteScript`.

`plan` is non-mutating. `install` refuses `unsupported` combinations and requires an explicit experimental opt-in for combinations that have not cleared all support gates. Strategies that still lack a verified dedicated adapter fail closed instead of guessing an installer.

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
- `apple`

### Containers / infrastructure

- `docker`
- `podman`
- `kubectl`
- `opentofu`

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

The `full` profile never opts into `experimental` environments by itself. Unsupported and target-only entries are never converted into host installations.

## Platform model

Primary implementation targets:

- Windows 11 and serviced Windows 10 clients, x64/ARM64 where the individual environment supports it;
- WSL2 with Debian, Ubuntu, Arch Linux, openSUSE and Kali;
- Debian/Ubuntu/Mint/Kali/Raspberry Pi OS;
- Arch/Manjaro;
- Fedora/RHEL/Rocky/Alma;
- openSUSE;
- Alpine;
- macOS Intel and Apple Silicon.

Research/validation targets:

- FreeBSD, OpenBSD, NetBSD, DragonFly BSD;
- illumos, Oracle Solaris, AIX.

Extended Unix entries remain experimental or target-only until validated on authoritative target systems. Cross-compilation capability is represented separately from host support.

## Security model

The implementation follows the gates in [`AGENTS.md`](AGENTS.md). In particular:

- no silent unsupported fallback;
- no automatic `curl | sh` / `irm | iex` execution;
- source provenance is recorded in manifests;
- package-manager and official-vendor mechanisms are preferred;
- remote scripts must be downloaded and inspected before execution;
- checksum/signature mismatches are hard failures where upstream integrity metadata is available;
- privilege escalation is scoped to operations that require it;
- `plan` never mutates the host;
- destructive uninstall is refused where ownership cannot be established safely;
- Windows Server exclusions are evaluated independently from Windows client support where upstream requires it.

## Repository layout

```text
AGENTS.md               governance contract and mandatory gates
bin/                    user-facing POSIX and PowerShell orchestrators
bootstrap/              minimal host bootstrap scripts
manifests/              platform/environment catalog and schema
profiles/               composable environment selections
research/               dated upstream support/source research
scripts/                validation/security helpers
tests/                  manifest and CLI tests
.github/workflows/       CI gates
```

## Current automation boundary

Package-manager and selected official-script strategies have executable adapters. `official-archive`, product-specific `manual`, source-build, VM and container strategies are represented in plans but intentionally fail closed until their download, integrity, ownership, PATH and uninstall contracts are implemented per product.

This boundary prevents a broad platform matrix from becoming an unverified collection of download commands.

## Upstream research

The initial support matrix was refreshed on **2026-08-10** from primary upstream documentation. See [`research/upstream-sources.md`](research/upstream-sources.md). Runtime versions and EOL information are intentionally not assumed permanent; manifests carry research dates and must be revalidated before version-sensitive changes.

## License

MIT — see [`LICENSE`](LICENSE).

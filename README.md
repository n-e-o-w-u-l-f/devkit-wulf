# devkit-wulf

Secure, manifest-driven multi-platform developer environment bootstrapper and orchestrator for Windows, WSL2, Linux, macOS, BSD and explicitly researched extended Unix targets.

> **Status:** pre-1.0 bootstrap. Platform/environment combinations remain `experimental` until their required CI or target-system gates pass. The repository intentionally does not advertise unverified combinations as supported.

## Design

`devkit-wulf` separates:

- host detection;
- package-manager adapters;
- environment metadata;
- installation planning;
- mutation;
- verification;
- state tracking;
- CI/security gates.

Support status and execution strategy are modeled independently. A combination may therefore be `support: experimental` while using `strategy: native`, `wsl2`, `vm`, `container`, `source`, or `target-only`.

## Quick start

### Linux / macOS / BSD / Unix

```sh
./bootstrap/linux.sh        # Linux
./bootstrap/macos.sh        # macOS
./bin/devkit-wulf detect
./bin/devkit-wulf list
./bin/devkit-wulf plan python
./bin/devkit-wulf install python --experimental
./bin/devkit-wulf verify python
./bin/devkit-wulf doctor
```

Use the matching bootstrap script for BSD, Solaris/illumos, or AIX. Bootstraps install only the small parser/tooling prerequisites needed by the orchestrator and do not install developer profiles.

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

### WSL2

Run the Linux CLI inside the selected WSL distribution. WSL distributions are detected independently from the Windows host. `devkit-wulf` never silently creates a WSL distribution or converts WSL1 to WSL2.

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

`plan` is non-mutating. `install` refuses `unsupported` combinations and requires an explicit experimental opt-in for combinations that have not yet cleared all support gates.

## Initial environments

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
- `vscode`
- `visualstudio`
- `android`
- `flutter`
- `apple`
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

The `full` profile never opts into `experimental` environments by itself.

## Platform model

Tier-1 implementation targets:

- Windows 11 and serviced Windows 10 clients, x64/ARM64 where the individual environment supports it;
- WSL2 with Debian, Ubuntu, Arch Linux, openSUSE, Kali;
- Debian/Ubuntu/Mint/Kali/Raspberry Pi OS;
- Arch/Manjaro;
- Fedora/RHEL/Rocky/Alma;
- openSUSE;
- Alpine;
- macOS Intel and Apple Silicon.

Research/validation targets:

- FreeBSD, OpenBSD, NetBSD, DragonFly BSD;
- illumos, Oracle Solaris, AIX.

Extended Unix entries remain experimental or target-only until validated on authoritative target systems.

## Security model

The implementation follows the gates in [`AGENTS.md`](AGENTS.md). In particular:

- no silent unsupported fallback;
- no automatic `curl | sh` / `irm | iex` execution;
- source provenance is recorded in manifests;
- package-manager and official-vendor mechanisms are preferred;
- remote scripts must be downloaded and inspected before execution;
- checksum/signature mismatches are hard failures;
- privilege escalation is scoped to individual package-manager operations;
- `plan` never mutates the host;
- destructive uninstall is refused where ownership cannot be established safely.

## Repository layout

```text
bin/                    user-facing CLIs
bootstrap/              minimal host bootstrap scripts
lib/                    shared orchestration logic
manifests/              platform/environment catalog and schemas
profiles/               composable environment selections
research/               dated upstream support/source research
scripts/                validation/security helpers
tests/                  manifest and CLI tests
.github/workflows/       CI gates
```

## Upstream research

The initial support matrix was refreshed on **2026-08-10** from primary upstream documentation. See [`research/upstream-sources.md`](research/upstream-sources.md). Runtime versions and EOL information are intentionally not assumed permanent; manifests carry research dates and must be revalidated before version-sensitive changes.

## License

MIT — see [`LICENSE`](LICENSE).

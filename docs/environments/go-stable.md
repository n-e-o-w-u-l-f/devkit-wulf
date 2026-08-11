# Go stable system-native environment

Research date: **2026-08-11**

Selector:

```text
go@stable
```

Support state: **experimental** on every active adapter. Adapter presence does not promote support.

## Architecture

The shared environment contract is:

```text
environments/go/stable.json
```

POSIX verified-artifact handling uses:

```text
manifests/go-artifact.json
lib/go-artifact.sh
```

Native Windows uses its own reviewed archive contract and PowerShell helper:

```text
manifests/go-windows.json
lib/go-windows.ps1
```

This split is deliberate. The selector expresses shared Go-stable intent, while each execution domain uses a host-native reviewed artifact transaction. The generic unversioned `go` environment remains separate and continues to use its declared catalog strategy.

## Native Linux

```sh
./installers/linux/devkit-wulf.sh plan go@stable
./installers/linux/devkit-wulf.sh install go@stable --experimental
./installers/linux/devkit-wulf.sh verify go@stable
```

Adapter:

```text
installers/linux/environments/go-stable.sh
```

Reviewed architectures are inherited exactly from the POSIX Go artifact manifest:

```text
amd64
arm64
riscv64
ppc64le
s390x
```

The adapter performs no privilege escalation, package-manager mutation, or persistent PATH editing. Native Linux rejects WSL; WSL has its own release entrypoint.

## WSL2

```sh
./installers/wsl/devkit-wulf.sh plan go@stable
./installers/wsl/devkit-wulf.sh install go@stable --experimental
./installers/wsl/devkit-wulf.sh verify go@stable
```

Adapter:

```text
installers/wsl/environments/go-stable.sh
```

The WSL adapter proves the WSL domain and delegates to the exact Linux Go payload with explicit WSL guards. It does not duplicate artifact logic and does not invoke a Windows installer inside the Linux distribution.

## macOS

```sh
./installers/macos/devkit-wulf.sh plan go@stable
./installers/macos/devkit-wulf.sh install go@stable --experimental
./installers/macos/devkit-wulf.sh verify go@stable
```

Adapter:

```text
installers/macos/environments/go-stable.sh
```

Reviewed architectures:

```text
amd64
arm64
```

The macOS adapter uses the POSIX verified Go artifact helper with macOS-native host/architecture mapping and SHA/download primitives. No Homebrew package is installed for this selector.

## Windows

```powershell
.\installers\windows\devkit-wulf.ps1 plan 'go@stable'
.\installers\windows\devkit-wulf.ps1 install 'go@stable' -Experimental
.\installers\windows\devkit-wulf.ps1 verify 'go@stable'
```

Adapter:

```text
installers/windows/environments/go-stable.ps1
```

Contract/helper:

```text
manifests/go-windows.json
lib/go-windows.ps1
```

Reviewed architectures:

```text
amd64
arm64
```

The native Windows route resolves official Go release metadata from `go.dev`, selects the ZIP artifact for the exact architecture, validates the release SHA-256, rejects unsafe archive paths, installs to the user-local devkit-wulf destination, records managed ownership/integrity state, and refuses foreign destinations. It does not reuse the POSIX tar installer or an MSI transaction and does not persistently mutate PATH.

The route is **experimental** and still requires explicit `-Experimental` opt-in for installation.

### CI reconciliation gate

The semantic validator and Windows release entrypoint require this native route, but `.github/workflows/go-stable-system-native.yml` still contains the previous Windows fail-closed assertion. This is tracked in issue #35. Until that workflow is reconciled and hosted CI is runnable, do not treat the Windows lane as CI-promoted support.

## Extended platforms

The shared selector marks BSD, Solaris/illumos and AIX unsupported for this artifact path. Go cross-compilation targets are not proof that devkit-wulf has a verified host installer for those systems.

## Shared verified behavior

For active hosts, reviewed Go artifact paths provide:

- official stable release-index resolution;
- exact host OS/architecture matching;
- SHA-256 integrity validation from official release metadata;
- archive safety validation;
- user-local installation;
- no implicit privilege escalation;
- no persistent PATH mutation;
- ownership markers and critical `go`/`gofmt` hashes;
- managed verification;
- offline/idempotent second installation when the managed installation still verifies;
- refusal to adopt a foreign destination;
- no automatic upgrade of an existing managed toolchain.

`install` remains experimental at every active system-native boundary.

## Release-facing structure

```text
go@stable shared intent
        │
        ├── Linux  -> POSIX verified artifact adapter
        ├── WSL2   -> WSL domain adapter -> Linux adapter
        ├── macOS  -> POSIX verified artifact adapter
        └── Windows-> native PowerShell verified artifact adapter
```

This preserves shared selector semantics without pretending that one archive format, shell helper, or host implementation is portable across every operating system.

See also `docs/environments/go-artifact.md`, `docs/installer-architecture.md`, and `docs/REPOSITORY-STATUS.md`.

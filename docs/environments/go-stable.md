# Go stable system-native environment

Research date: **2026-08-11**

Selector:

```text
go@stable
```

## Architecture

The shared environment contract is:

```text
environments/go/stable.json
```

The already-reviewed integrity/download contract remains:

```text
manifests/go-artifact.json
lib/go-artifact.sh
```

This split is deliberate. The shared helper resolves the verified Go release metadata, SHA-256 and safe archive transaction. Release-facing system adapters prove the host/domain and map the user command to that helper.

The generic `go` environment remains unchanged and continues to use its existing package-manager strategy. `go@stable` is a separate experimental user-local verified-artifact path.

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

Verified architectures are inherited exactly from `manifests/go-artifact.json`:

```text
amd64
arm64
riscv64
ppc64le
s390x
```

The adapter performs no `sudo`/`doas`, no package-manager mutation and no PATH editing. It supplies the portable caller primitives required by `lib/go-artifact.sh`, then the existing helper performs release resolution, SHA-256, archive safety, ownership and idempotency checks.

Native Linux rejects WSL. WSL uses its own release entrypoint.

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

The WSL adapter only proves the WSL domain and delegates to the exact Linux Go adapter with explicit WSL flags. It does not duplicate download, SHA or extraction logic and does not invoke a Windows installer inside the Linux distribution.

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

Verified architectures:

```text
amd64
arm64
```

The macOS adapter uses the same verified Go artifact helper but provides macOS host/architecture mapping and native SHA/download primitives. No Homebrew package is installed for this selector; the artifact remains isolated under the devkit-wulf user-local destination defined by the verified manifest.

## Windows and extended platforms

`go@stable` is explicitly not enabled on Windows by this contract. The current verified Go artifact catalog contains Linux and macOS targets only.

The shared selector also marks BSD, Solaris/illumos and AIX unsupported for this artifact path. Go cross-compilation targets are not treated as proof that devkit-wulf has a verified host installer for those systems.

A future Windows implementation should be a separate Windows-native archive/package contract, not a reuse of the Linux tar installer.

## Shared verified behavior

For active hosts, the existing artifact helper provides:

- official stable release-index resolution;
- exact host OS/architecture matching;
- SHA-256 from the release metadata;
- strict tar-root/type validation;
- rejection of symlinks/hardlinks/special files;
- user-local installation;
- no privilege escalation;
- no PATH mutation;
- ownership marker and critical `go`/`gofmt` hashes;
- exact managed verification;
- fully offline second installation when the managed installation verifies;
- no automatic upgrade of an existing managed toolchain.

`install` remains experimental and therefore requires an explicit `--experimental` opt-in at the system-native adapter boundary.

## Relationship to system-specific packaging

The shared Go artifact transaction is portable code, not a universal executable. The release-facing structure remains:

```text
go@stable shared intent / verified artifact contract
        │
        ├── Linux entrypoint -> Linux adapter
        ├── WSL entrypoint   -> WSL domain adapter -> Linux adapter
        ├── macOS entrypoint -> macOS adapter
        └── Windows          -> explicit unsupported gate
```

This preserves reusable security logic without claiming that one Linux/macOS shell artifact is a Windows `.exe` or that every Go-supported compilation target is a supported installer host.

See also `docs/environments/go-artifact.md` and `docs/installer-architecture.md`.

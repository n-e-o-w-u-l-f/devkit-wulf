# Rust stable system-native environment

Research date: **2026-08-11**

Selector:

```text
rust@stable
```

## Shared contract and verified bootstrap

The shared selector contract is:

```text
environments/rust/stable.json
```

The existing reviewed rustup bootstrap contract remains:

```text
manifests/rustup-artifact.json
lib/rustup-artifact.sh
```

The helper downloads the platform-specific `rustup-init` binary and its `.sha256` metadata from the pinned Rust distribution source, verifies the binary before execution and installs an isolated stable toolchain with `--no-modify-path`.

This selector does **not** execute `sh.rustup.rs` and does not use a streamed `curl | sh` or `wget | sh` path.

The unversioned `rust` environment remains unchanged and retains its existing generic/package-manager behavior.

## Native Linux

```sh
./installers/linux/devkit-wulf.sh plan rust@stable
./installers/linux/devkit-wulf.sh install rust@stable --experimental
./installers/linux/devkit-wulf.sh verify rust@stable
```

Adapter:

```text
installers/linux/environments/rust-stable.sh
```

The current verified Linux rustup contract is intentionally restricted to **glibc** hosts and these architectures:

```text
amd64 -> x86_64-unknown-linux-gnu
arm64 -> aarch64-unknown-linux-gnu
```

The adapter proves glibc using `getconf GNU_LIBC_VERSION`. Alpine/musl and other libc variants are not treated as interchangeable Linux hosts; they require separate reviewed target contracts.

The Rust toolchain is isolated under devkit-wulf-owned user data paths for `CARGO_HOME` and `RUSTUP_HOME`. The managed Cargo bin directory must already be present in the current process PATH. devkit-wulf does not edit shell startup files.

## WSL2

```sh
./installers/wsl/devkit-wulf.sh plan rust@stable
./installers/wsl/devkit-wulf.sh install rust@stable --experimental
./installers/wsl/devkit-wulf.sh verify rust@stable
```

The WSL adapter proves the WSL domain and delegates to the exact Linux adapter. Therefore the same glibc/architecture contract applies inside WSL. A Windows rustup executable is not invoked inside the Linux distribution.

## macOS

```sh
./installers/macos/devkit-wulf.sh plan rust@stable
./installers/macos/devkit-wulf.sh install rust@stable --experimental
./installers/macos/devkit-wulf.sh verify rust@stable
```

Adapter:

```text
installers/macos/environments/rust-stable.sh
```

Verified target mappings:

```text
amd64 -> x86_64-apple-darwin
arm64 -> aarch64-apple-darwin
```

The adapter uses the same reviewed rustup-init SHA-256 transaction while keeping macOS host/architecture detection and download/hash primitives system-specific.

## Windows

`rust@stable` is explicitly **not enabled** by this selector on Windows. The currently reviewed rustup artifact manifest contains Linux and macOS binaries only.

That does not mean Rust lacks a Windows toolchain. It means devkit-wulf has not yet promoted a Windows-native PowerShell/rustup-init artifact transaction into this reviewed selector. A future Windows adapter should download and verify the correct Windows rustup-init artifact using a native PowerShell contract rather than trying to run the POSIX installer.

The Windows release entrypoint therefore fails closed before generic fallback when `rust@stable` is requested.

## BSD and extended Unix

BSD, Solaris/illumos and AIX remain unsupported for this selector. Rust compiler target availability is not equivalent to a verified devkit-wulf host installer.

## Managed verification and idempotency

The reviewed helper binds the installation marker to the hashes of the managed:

```text
rustup
rustc
cargo
```

Verification executes those exact managed binaries using the isolated `CARGO_HOME` and `RUSTUP_HOME`.

If an exact managed installation already verifies, a second install is handled as an observation and does not rerun the bootstrap. A foreign, modified or partially managed installation is a conflict rather than an automatic replacement/upgrade target.

## Security properties

- direct verified `rustup-init`, not remote script execution;
- SHA-256 before execution;
- `--profile minimal`;
- stable default toolchain;
- `--no-modify-path`;
- no root, sudo or doas;
- user-local isolated homes;
- marker-bound binary hashes;
- no silent adoption of foreign managed homes;
- no automatic upgrade/replacement semantics;
- experimental install requires explicit `--experimental`.

## Responsibility split

```text
rust@stable shared environment contract
        │
        ├── reviewed rustup artifact/SHA helper
        │
        ├── Linux adapter ── glibc + Linux architecture gate
        ├── WSL adapter ──── WSL proof -> Linux adapter
        ├── macOS adapter ─── Darwin architecture gate
        └── Windows ──────── explicit unsupported until native contract exists
```

This preserves reusable verification logic without turning a POSIX installer into a falsely universal executable.

See also `docs/environments/rustup-artifact.md` and `docs/installer-architecture.md`.

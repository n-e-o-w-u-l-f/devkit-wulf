# Windows native rustup-init artifact contract

Research date: **2026-08-11**

This contract prepares the native Windows implementation used by the `rust@stable` selector. It is intentionally separate from the existing POSIX rustup artifact implementation.

## Native artifacts

Manifest:

```text
manifests/rustup-windows.json
```

PowerShell helper:

```text
lib/rustup-windows.ps1
```

Environment adapter:

```text
installers/windows/environments/rust-stable.ps1
```

The current reviewed target mappings are:

```text
amd64 -> x86_64-pc-windows-msvc
arm64 -> aarch64-pc-windows-msvc
```

For each target, the helper constructs only these official Rust distribution URLs:

```text
https://static.rust-lang.org/rustup/dist/<target>/rustup-init.exe
https://static.rust-lang.org/rustup/dist/<target>/rustup-init.exe.sha256
```

The checksum sidecar is downloaded before the executable. `rustup-init.exe` is executed only after its local SHA-256 exactly matches the official sidecar.

No `sh.rustup.rs`, `curl | sh`, `Invoke-Expression` or POSIX shell bootstrap is used on Windows.

## User-local isolation

The selector-owned Windows root is:

```text
%LOCALAPPDATA%\devkit-wulf
```

with isolated homes:

```text
CARGO_HOME  = %LOCALAPPDATA%\devkit-wulf\cargo
RUSTUP_HOME = %LOCALAPPDATA%\devkit-wulf\rustup
```

The managed command directory is:

```text
%LOCALAPPDATA%\devkit-wulf\cargo\bin
```

That directory must already be present in the **current process PATH**. devkit-wulf does not change persistent user/machine environment variables and does not edit shell startup configuration.

## Installer arguments

The verified executable receives only the manifest-pinned non-interactive arguments:

```text
-y --profile minimal --default-toolchain stable --no-modify-path
```

The adapter therefore requests the stable toolchain with the minimal rustup profile and disables rustup's PATH modification.

## Build-tool prerequisites

This artifact contract installs and verifies the Rust/rustup toolchain payload only. It does not silently install Visual Studio, MSVC Build Tools, the Windows SDK, CMake, Ninja or other native linker/toolchain prerequisites.

Projects that require the MSVC linker or native libraries must satisfy those through the separate Windows C/C++/Build Tools environment contracts. Keeping those responsibilities separate prevents `rust@stable` from becoming an implicit machine-wide Visual Studio installer.

## Conflict gate before network

If either selector-owned `CARGO_HOME` or `RUSTUP_HOME` already exists, installation does not immediately download anything.

- if both homes exist and exact marker/hash/runtime verification succeeds, the installation is treated as an offline idempotent observation;
- otherwise the operation fails as GATE-08 and does not adopt or overwrite the existing homes.

This prevents a pre-existing foreign rustup installation under the devkit selector root from being silently claimed.

## Managed marker

After a successful verified bootstrap, the helper records:

- environment `rust`;
- selector `rust@stable`;
- platform `windows`;
- normalized architecture;
- exact MSVC target triple;
- official `rustup-init.exe` source URL;
- verified installer SHA-256;
- SHA-256 values for:
  - `cargo/bin/rustup.exe`
  - `cargo/bin/rustc.exe`
  - `cargo/bin/cargo.exe`;
- `privileged: false`;
- `path_mutation: false`.

State history is written separately to a user-local JSONL file and rejects state-directory/file reparse points.

## Runtime verification

Verification does not trust a global `rustc`, `cargo` or `rustup` found elsewhere on PATH. It executes the exact selector-owned files while temporarily setting the exact selector-owned `CARGO_HOME` and `RUSTUP_HOME`.

It requires:

```text
rustup.exe --version          -> rustup ...
rustc.exe --version           -> rustc ...
cargo.exe --version           -> cargo ...
rustup.exe show active-toolchain -> stable...
```

The critical executable hashes must still match the ownership marker before those runtime checks are accepted.

## Failure and rollback boundary

The downloaded temporary `rustup-init.exe` is always removed explicitly.

If rustup mutates the selector-owned homes and then fails before a valid ownership marker is written, devkit-wulf does **not** recursively delete those homes automatically. The failure is surfaced as a partial managed-home mutation requiring explicit inspection/remediation.

This avoids claiming a safe destructive rollback when rustup may have created state whose exact ownership/dependency graph is not yet proven.

## Experimental gate

The direct adapter supports:

```powershell
.\installers\windows\environments\rust-stable.ps1 plan
.\installers\windows\environments\rust-stable.ps1 install -Experimental
.\installers\windows\environments\rust-stable.ps1 verify
```

`install` requires `-Experimental` **before** manifest/helper loading or checksum/network work.

A separate routing PR activates this native implementation from the top-level Windows `rust@stable` selector after the artifact contract has been reviewed/merged.

## Offline regression fixture

`tests/test_rustup_windows.ps1` performs no live Rust download. It supplies local checksum/artifact fixtures and replaces only the bootstrap execution inside the test session with generated managed command stubs.

The fixture covers:

- Windows target triple/URL mapping;
- sidecar SHA-256 parsing;
- non-mutating plan;
- hard installer hash verification before bootstrap;
- exact pinned bootstrap arguments;
- managed marker/runtime verification;
- offline second installation;
- critical executable tampering;
- foreign-home conflict before network;
- malformed checksum rejection.

The production helper is still responsible for executing the real verified `rustup-init.exe`; the fixture deliberately tests the surrounding transaction without installing Rust on the CI runner.

# Verified rustup-init bootstrap contract

Research/update date: **2026-08-11**

Status: **experimental**

## Goal

This contract replaces the security mechanism behind Rust's existing POSIX `official-script` paths with a directly downloaded, SHA-256-verified `rustup-init` executable.

It does **not** yet change the central `rust` environment routing and does not promote support.

## Official distribution source

Pinned source root:

```text
https://static.rust-lang.org/rustup/dist
```

The adapter constructs only the official `rustup-init` artifact and adjacent `.sha256` URL for the selected target triple.

Mapped targets:

| Host | devkit arch | rustup target triple |
|---|---|---|
| Linux glibc | amd64 | `x86_64-unknown-linux-gnu` |
| Linux glibc | arm64 | `aarch64-unknown-linux-gnu` |
| macOS | amd64 | `x86_64-apple-darwin` |
| macOS | arm64 | `aarch64-apple-darwin` |

Linux use is explicitly gated to glibc. Alpine's existing package-manager path is not replaced by this artifact contract.

## No remote installer script

The helper does not download or execute `sh.rustup.rs`.

Instead it:

1. constructs the exact official `rustup-init` URL;
2. downloads the adjacent `.sha256` file;
3. validates that checksum metadata contains a 64-hex SHA-256;
4. downloads `rustup-init`;
5. computes the local SHA-256 and requires an exact match;
6. only then marks the verified staging file executable;
7. invokes it directly with fixed arguments.

Installer arguments are pinned to:

```text
-y
--profile minimal
--default-toolchain stable
--no-modify-path
```

## User-scoped isolation

The adapter does not use the user's default `~/.cargo` or `~/.rustup` directories.

Managed homes:

```text
CARGO_HOME=$HOME/.local/share/devkit-wulf/cargo
RUSTUP_HOME=$HOME/.local/share/devkit-wulf/rustup
```

Expected PATH directory:

```text
$HOME/.local/share/devkit-wulf/cargo/bin
```

Ownership marker:

```text
$HOME/.local/share/devkit-wulf/cargo/.devkit-wulf-rustup.json
```

The helper passes `--no-modify-path` and never edits shell startup files. The managed `cargo/bin` path must already be present in the current PATH before mutation.

No root/sudo/doas privilege is used.

## Conflict policy

A pre-existing managed Cargo or Rustup home is never adopted implicitly.

If either managed directory already exists, the helper requires a valid devkit ownership marker plus exact hashes for the managed `rustup`, `rustc` and `cargo` executables. Otherwise GATE-08 fails before artifact download.

The adapter deliberately avoids the user's conventional Rustup homes, so unrelated existing Rust installations do not need to be removed or modified.

## Managed verification

Offline managed verification checks:

- supported platform/architecture mapping;
- glibc on Linux;
- non-symlink managed Cargo/Rustup homes;
- a non-symlink ownership marker;
- publisher/environment/platform/architecture/target/source bindings;
- installer SHA-256 syntax;
- current SHA-256 of `rustup`, `rustc` and `cargo` against the marker;
- exact managed binary execution for `rustup --version`, `rustc --version` and `cargo --version`.

A modified managed binary invalidates verification.

## Idempotency

If the managed installation already passes marker/hash verification, a second install performs no network download and records an observation instead of a mutation.

This contract intentionally does not implement automatic Rustup/toolchain upgrades. Upgrade semantics can be added later as a separate reviewed transaction.

## Failure / rollback boundary

`rustup-init` can create several files across `CARGO_HOME` and `RUSTUP_HOME`. The helper therefore records `mutation-intent` before execution.

If `rustup-init` fails, the helper records an incomplete state and retains the user-scoped partial directories for inspection rather than pretending destructive rollback is always safe.

`safe_remove` remains false.

## State

Detailed state is appended to:

```text
<devkit-wulf-state>/rustup-artifact.jsonl
```

State directory/file symlinks are refused.

## Current integration boundary

The existing `rust` environment remains unchanged:

- Debian/Fedora/RHEL/openSUSE/macOS remain `experimental` `official-script` in the central catalog until routing changes;
- Arch/Alpine/FreeBSD/OpenBSD retain their package-manager paths.

A future central-routing PR can replace the effective POSIX `official-script` mechanism with this verified artifact only after exact host/platform gates are reviewed.

## Offline fixture

The fixture uses a HOME directory containing spaces and verifies:

- target triple resolution;
- official source/checksum URL construction;
- non-mutating plan;
- caller-variable namespace isolation when the helper is sourced;
- SHA-256 before execution;
- fixed `--no-modify-path` installer arguments;
- marker/hash verification;
- offline idempotent second install;
- binary tamper rejection;
- foreign managed-home refusal before network;
- PATH refusal before network;
- checksum mismatch refusal;
- state symlink refusal;
- Linux glibc gate.

## Upstream references

- Rust installation: https://www.rust-lang.org/tools/install
- rustup documentation: https://rust-lang.github.io/rustup/
- rustup book installation: https://rust-lang.github.io/rustup/installation/index.html
- Rust static distribution service: https://static.rust-lang.org/rustup/dist/

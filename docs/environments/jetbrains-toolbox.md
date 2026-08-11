# JetBrains Toolbox environment

Research date: **2026-08-11**

## Support boundary

The `jetbrains` environment remains **experimental**.

The central POSIX CLI now activates the managed Toolbox adapter only for the exact Linux platform entries already present in the environment catalog:

- Debian: `amd64`, `arm64`;
- Fedora: `amd64`, `arm64`.

No Linux-family inheritance is used for JetBrains Toolbox. Ubuntu, Linux Mint, Kali, RHEL, Rocky, AlmaLinux, openSUSE and other Linux platforms remain unsupported until they receive their own researched environment entry.

Windows retains its native package path and macOS retains its separately declared package-manager path.

The Linux Toolbox route is desktop-oriented and is **not enabled inside WSL2**. On WSL2, central plan/install/verify fail closed rather than installing a Linux desktop Toolbox instance implicitly.

## Central CLI

On exact native Debian/Fedora targets the effective strategy is:

```text
jetbrains-toolbox
```

Typical flow:

```sh
devkit-wulf plan jetbrains
devkit-wulf install jetbrains --experimental
devkit-wulf verify jetbrains
```

`install` still requires explicit experimental opt-in.

`plan jetbrains` resolves the current Toolbox release from JetBrains' pinned release API, but performs no persistent host mutation. `verify jetbrains` is offline with respect to release discovery and validates only the devkit-managed installation.

## Official release service

Pinned endpoint:

```text
https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release
```

Product code: `TBA`.

Linux download mappings:

```text
amd64 -> linux
arm64 -> linuxARM64
```

Each selected release must provide an archive `link` and `checksumLink`. Accepted HTTPS download hosts are limited to:

```text
download.jetbrains.com
download-cdn.jetbrains.com
```

## Archive and integrity contract

The Linux archive must be a `tar.gz` with the expected versioned root:

```text
jetbrains-toolbox-<version>/
```

Only this executable is selected:

```text
jetbrains-toolbox-<version>/jetbrains-toolbox
```

The adapter rejects absolute paths, backslash paths, `..` traversal and entries outside the expected root. The extracted executable must be a regular non-symlink executable.

Integrity sequence:

1. resolve release metadata from the pinned JetBrains service;
2. resolve the exact architecture download key;
3. validate archive/checksum hosts;
4. download and validate SHA-256 metadata;
5. download the archive and verify SHA-256;
6. validate archive paths;
7. extract only the expected executable;
8. calculate the executable SHA-256;
9. install the user-local binary;
10. run managed verification before recording success.

No checksum or TLS bypass is supported.

## User-local installation

Destination:

```text
$HOME/.local/bin/jetbrains-toolbox
```

Ownership marker:

```text
$HOME/.local/bin/.jetbrains-toolbox.devkit-wulf.json
```

`$HOME/.local/bin` must already exist, be writable, not be a symbolic link and already be present in the current `PATH`.

The adapter uses no root privileges and performs no PATH or shell-startup mutation.

## Managed verification

Central `verify jetbrains` delegates to `verify_jetbrains_toolbox` on the exact Debian/Fedora native route.

Verification requires:

- a regular non-symlink managed executable;
- a regular non-symlink ownership marker;
- marker environment `jetbrains` and publisher `JetBrains s.r.o.`;
- a valid recorded version and archive SHA-256;
- the current executable SHA-256 to match the marker;
- the managed executable's `--version` command to succeed with output.

A modified executable or missing marker fails verification. A different global `jetbrains-toolbox` executable cannot satisfy the managed gate.

On unsupported Linux platforms, `verify jetbrains` fails closed instead of falling back to generic PATH verification. macOS retains its exact separately declared generic package-manager verification path.

## Conflict and idempotency policy

The adapter never adopts or overwrites an arbitrary existing Toolbox executable.

A repeated installation is idempotent only when the current release still matches the exact devkit-owned version/source/archive hash and the executable hash remains unchanged.

A newly published Toolbox release does not silently overwrite an existing managed installation; an explicit future upgrade/migration path is required.

## State and cleanup

Detailed Toolbox records are appended to:

```text
<devkit-wulf-state>/jetbrains-toolbox.jsonl
```

The state directory/file refuse symbolic links. Central CLI state is recorded only after managed verification succeeds.

Staging cleanup is bounded to the exact files/directories created by the transaction; the Toolbox helper does not recursively delete an arbitrary staging tree.

## Current integration status

Implemented and centrally routed:

- manifest and JSON Schema;
- verified release resolver;
- Linux amd64/arm64 download mapping;
- checksum enforcement;
- archive safety gate;
- user-local installation;
- marker/idempotency gate;
- offline managed verification;
- exact Debian/Fedora central routing;
- WSL2 fail-closed desktop gate;
- central CLI regression tests;
- dedicated workflow covering central CLI + standalone offline fixture.

Not yet implemented:

- removal ownership semantics;
- automatic upgrade/migration between Toolbox releases;
- additional Linux distribution targets without separate research.

## Upstream references

- JetBrains Toolbox App: https://www.jetbrains.com/toolbox-app/
- JetBrains Toolbox documentation: https://www.jetbrains.com/help/toolbox-app/
- JetBrains product release service: https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release

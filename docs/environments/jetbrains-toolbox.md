# JetBrains Toolbox environment

Research date: **2026-08-11**

## Support boundary

The existing `jetbrains` environment remains `experimental`.

This implementation adds a verified, manifest-driven **Linux JetBrains Toolbox artifact layer** for the platform/architecture combinations already declared as experimental `official-archive` paths:

- Debian-family hosts: `amd64`, `arm64`;
- Arch-family hosts: `amd64`, `arm64`;
- Fedora-family hosts: `amd64`, `arm64`;
- RHEL-family hosts: `amd64`, `arm64`;
- openSUSE-family hosts: `amd64`, `arm64`.

It does not replace the existing Windows WinGet path or macOS package-manager path.

The helper is deliberately not advertised as centrally activated CLI support until its manifest and helper are wired into the main orchestrator atomically. Until then, the normal `official-archive` path remains fail-closed.

## Official release service

JetBrains publishes a machine-readable product release service. The Toolbox App product code is `TBA`.

The pinned release endpoint is:

```text
https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release
```

The current release response contains platform-specific download objects. The Linux mappings used by this adapter are:

```text
amd64 -> linux
arm64 -> linuxARM64
```

Each selected object must contain both:

- `link` — the archive download URL;
- `checksumLink` — the corresponding SHA-256 metadata URL.

The adapter accepts archive and checksum URLs only from the explicitly allowlisted JetBrains download hosts:

```text
download.jetbrains.com
download-cdn.jetbrains.com
```

HTTPS is mandatory.

## Archive contract

The Linux Toolbox download is expected to be a `tar.gz` archive with one versioned root:

```text
jetbrains-toolbox-<version>/
```

The executable selected for installation is exactly:

```text
jetbrains-toolbox-<version>/jetbrains-toolbox
```

The version returned by the release service must satisfy the manifest's numeric release pattern before it may be substituted into the expected root directory name.

Before extraction, every archive entry must:

- be relative;
- remain under the exact expected versioned root;
- contain no `..` traversal component;
- contain no backslash path separator.

Only the expected Toolbox executable is extracted from the archive. The extracted executable must be a real regular file, not a symbolic link, and must be executable.

## Integrity

The adapter performs the following integrity sequence:

1. download release metadata from the pinned JetBrains release service;
2. resolve the exact Linux architecture key;
3. validate the selected archive/checksum hosts;
4. download the checksum metadata;
5. require a valid 64-hex SHA-256 value;
6. download the archive;
7. calculate the local archive SHA-256;
8. hard-fail on mismatch;
9. inspect the archive path layout;
10. extract only the expected executable;
11. calculate and track the executable SHA-256 separately.

No checksum or TLS bypass is supported.

## User-local installation

The planned destination is:

```text
$HOME/.local/bin/jetbrains-toolbox
```

The ownership marker is:

```text
$HOME/.local/bin/.jetbrains-toolbox.devkit-wulf.json
```

Before installation, `$HOME/.local/bin` must:

- already exist;
- be writable by the current user;
- not be a symbolic link;
- already be present in the current `PATH`.

The helper does not use root privileges and does not silently modify PATH or shell startup files.

## Conflict and idempotency policy

The helper never adopts or overwrites an arbitrary existing `jetbrains-toolbox` executable.

A second installation is treated as idempotent only when:

1. the destination is a regular non-symlink file;
2. the marker is a regular non-symlink file;
3. the marker environment is `jetbrains`;
4. the resolved version and exact archive source URL match;
5. the verified archive SHA-256 matches;
6. the current installed executable SHA-256 matches the executable SHA-256 recorded by the marker.

If any of those conditions fail, installation stops under GATE-08 and requires an explicit future upgrade/migration workflow.

A newly published Toolbox release therefore does not silently replace an existing managed installation.

## State tracking

The standalone helper writes append-only records to:

```text
<devkit-wulf-state>/jetbrains-toolbox.jsonl
```

Both the state directory and state file refuse symbolic links.

Records include:

- publisher;
- environment ID;
- action;
- version;
- archive source URL;
- checksum URL;
- destination;
- archive SHA-256;
- executable SHA-256;
- whether devkit-wulf created the destination;
- `path_mutation: false`.

## Verification

The existing environment contract verifies:

```text
jetbrains-toolbox --version
```

The offline fixture uses the same command shape after installation.

The Toolbox application itself may subsequently manage IDE installations, but installing Toolbox must never be treated as proof that every JetBrains IDE is supported on the host. IDE requirements remain product-specific.

## Current integration status

Implemented on the feature branch:

- manifest contract;
- JSON Schema;
- verified release resolver;
- Linux amd64/arm64 mapping;
- checksum enforcement;
- archive safety gate;
- user-local installation helper;
- marker/idempotency gate;
- offline integration fixture;
- semantic cross-check against the existing `jetbrains` environment.

Not yet activated in the main CLI:

- automatic routing from `devkit-wulf install jetbrains` to this helper;
- main artifact-catalog consolidation;
- removal ownership semantics.

Until central activation is merged, the existing CLI remains fail-closed for the Linux `official-archive` path.

## Upstream references

- JetBrains Toolbox App: https://www.jetbrains.com/toolbox-app/
- JetBrains Toolbox documentation: https://www.jetbrains.com/help/toolbox-app/
- JetBrains product release service: https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release

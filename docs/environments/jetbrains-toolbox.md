# JetBrains Toolbox environment

Research date: **2026-08-11**

## Support boundary

The existing `jetbrains` environment remains `experimental`.

The current environment catalog declares Linux `official-archive` entries for:

- Debian: `amd64`, `arm64`;
- Fedora: `amd64`, `arm64`.

The standalone Toolbox artifact manifest provides the corresponding Linux amd64/arm64 download-key mapping. That architecture mapping is not permission to generalize the adapter to every Linux distribution.

Windows retains its native package path and macOS retains its separately declared package-manager path. Linux derivatives or other distributions require an explicit environment entry before central automatic routing.

The helper is deliberately separate from central CLI activation until the routing change is merged atomically. Until then, the normal Linux `official-archive` path remains fail-closed.

## Official release service

JetBrains publishes a machine-readable product release service. The Toolbox App product code is `TBA`.

The pinned release endpoint is:

```text
https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release
```

The Linux mappings used by this adapter are:

```text
amd64 -> linux
arm64 -> linuxARM64
```

Each selected object must contain both an archive `link` and its `checksumLink`.

The adapter accepts those URLs only from:

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

The selected executable is exactly:

```text
jetbrains-toolbox-<version>/jetbrains-toolbox
```

The release-service version must satisfy the manifest's numeric release pattern before it is used in the expected root name.

Before extraction, every archive entry must be relative, remain under the exact expected versioned root, contain no `..` traversal component and contain no backslash path separator.

Only the expected Toolbox executable is extracted. It must be a regular non-symlink executable.

## Integrity

The adapter performs this integrity sequence:

1. download release metadata from the pinned JetBrains service;
2. resolve the exact Linux architecture key;
3. validate the selected archive/checksum hosts;
4. download checksum metadata;
5. require a valid SHA-256 value;
6. download the archive;
7. calculate and compare the local archive SHA-256;
8. inspect archive paths;
9. extract only the expected executable;
10. calculate and record the executable SHA-256;
11. run managed verification before installation is considered complete.

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

Before installation, `$HOME/.local/bin` must already exist, be writable, not be a symbolic link and already be present in the current `PATH`.

The helper uses no root privileges and does not silently modify PATH or shell startup files.

## Managed verification

`verify_jetbrains_toolbox <arch>` is offline with respect to release discovery. It validates the installed state rather than asking the current release service what is newest.

Verification requires:

- a regular non-symlink executable;
- a regular non-symlink devkit ownership marker;
- `environment: jetbrains` and publisher `JetBrains s.r.o.`;
- a syntactically valid recorded version;
- a valid recorded archive SHA-256;
- the current executable SHA-256 to equal the marker's recorded executable SHA-256;
- the managed executable's `--version` command to succeed and return output.

A modified executable or missing marker fails verification even when another `jetbrains-toolbox` command exists elsewhere in PATH.

## Conflict and idempotency policy

The helper never adopts or overwrites an arbitrary existing Toolbox executable.

A second installation is idempotent only when the current release still matches the exact devkit-owned marker/source/archive hash and the installed executable hash remains unchanged.

A newly published Toolbox release therefore does not silently replace an existing managed installation. An explicit future upgrade/migration workflow is required.

## State tracking

The helper writes append-only records to:

```text
<devkit-wulf-state>/jetbrains-toolbox.jsonl
```

Both state directory and state file refuse symbolic links.

Records include publisher, environment ID, action, version, source/checksum URLs, destination, archive/executable SHA-256, creation ownership and `path_mutation: false`.

## Staging cleanup

Installation staging is created under the already-approved `$HOME/.local/bin` directory. Cleanup is bounded to the exact archive, checksum file, archive listing, extracted Toolbox executable, versioned extraction directories and marker staging file created by the current transaction.

The helper no longer uses a recursive deletion of the whole staging tree.

## Verification contract

The environment-level command remains:

```text
jetbrains-toolbox --version
```

The managed helper additionally binds that execution to the devkit-owned file and marker hashes. Toolbox managing an IDE later is not proof that every JetBrains IDE is supported on the host; IDE requirements remain product-specific.

## Current integration status

Implemented:

- manifest and JSON Schema;
- verified release resolver;
- Linux amd64/arm64 download mapping;
- checksum enforcement;
- archive safety gate;
- user-local installation helper;
- marker/idempotency gate;
- offline managed verification;
- bounded staging cleanup;
- offline integration fixture;
- semantic cross-check against the existing `jetbrains` environment.

Still separate from this hardening change:

- automatic routing from `devkit-wulf install jetbrains` to the helper;
- removal ownership semantics.

## Upstream references

- JetBrains Toolbox App: https://www.jetbrains.com/toolbox-app/
- JetBrains Toolbox documentation: https://www.jetbrains.com/help/toolbox-app/
- JetBrains product release service: https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release

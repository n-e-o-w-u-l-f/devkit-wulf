# Verified Go toolchain artifact contract

Research/update date: **2026-08-11**

Status: **experimental**

## Goal

This contract adds a deterministic, user-local Go toolchain artifact path backed by Go's official release metadata and SHA-256 values.

It does **not** replace the existing central package-manager strategy yet and does not promote Go support.

## Official release metadata

Pinned release index:

```text
https://go.dev/dl/?mode=json
```

Pinned download base:

```text
https://go.dev/dl
```

The resolver selects the current stable release from the official JSON response and then requires one exact `kind == archive` file matching the mapped operating system and architecture.

The selected metadata supplies:

- Go version;
- archive filename;
- operating system;
- architecture;
- SHA-256.

The final archive URL is constructed only under `https://go.dev/dl/`.

## Verified target matrix

| Host | Architectures |
|---|---|
| Linux | amd64, arm64, riscv64, ppc64le, s390x |
| macOS | amd64, arm64 |

Upstream OS mapping:

```text
Linux -> linux
macOS -> darwin
```

The contract does not infer support for Windows, BSD, illumos, Solaris or AIX from Go's cross-compilation target list.

## User-local installation

Managed destination:

```text
$HOME/.local/share/devkit-wulf/go
```

Expected PATH directory:

```text
$HOME/.local/share/devkit-wulf/go/bin
```

Ownership marker:

```text
$HOME/.local/share/devkit-wulf/go/.devkit-wulf-go.json
```

The surrounding `$HOME/.local/share` path must already exist, be writable and not be a symbolic link. The managed Go `bin` directory must already be present in the current PATH.

The helper performs no root/sudo/doas elevation and does not modify PATH or shell startup files.

## Integrity sequence

The helper:

1. downloads the official Go release JSON;
2. selects the current stable release;
3. resolves one exact archive for host OS/architecture;
4. validates version and filename syntax;
5. requires a 64-hex SHA-256 from the official metadata;
6. downloads the archive from `go.dev`;
7. computes the local archive SHA-256;
8. requires an exact match before extraction;
9. validates tar structure;
10. extracts into a staging directory under the approved user-local parent;
11. validates `go` and `gofmt` before placement;
12. records marker hashes and verifies the installed toolchain.

No checksum or TLS bypass is supported.

## Tar safety

Before extraction the adapter inspects both archive names and tar entry types.

Every entry must:

- remain under the exact `go/` root;
- be relative;
- contain no backslash path separator;
- contain no `..` traversal component;
- be either a regular file or a directory.

Symlinks, hardlinks, devices and other special tar entry types are rejected. After extraction, a second defense-in-depth check rejects any symbolic link inside the staged Go tree.

## Conflict policy

A foreign existing destination is refused before release metadata is downloaded.

An existing managed destination is accepted only when its ownership marker and critical binary hashes verify. The adapter never adopts an arbitrary existing Go installation.

## Managed verification

Offline managed verification binds the ownership marker to:

- environment `go`;
- publisher `The Go Authors`;
- host platform and architecture;
- recorded Go version;
- official source URL;
- archive SHA-256;
- current SHA-256 values of `bin/go` and `bin/gofmt`.

The managed binaries must also pass:

```text
go version
go env GOHOSTOS GOHOSTARCH
```

A modified managed binary invalidates verification.

## Idempotency and upgrades

An exact second installation is fully offline: if the existing managed installation verifies, no release-index or archive download occurs and the transaction records an observation.

This contract intentionally does not auto-upgrade an existing managed Go toolchain. Upgrade/migration semantics remain a separate future transaction.

## State

Detailed state is appended to:

```text
<devkit-wulf-state>/go-artifact.jsonl
```

State directory/file symlinks are refused.

Typical actions:

```text
mutation-intent
installed-verified
observed-managed
```

## Staging cleanup

Staging directories are created only under the approved devkit-wulf user data parent with a `.devkit-wulf-go.*` name. Recursive cleanup is allowed only after the helper verifies that exact parent/prefix boundary and that the staging path is not a symlink.

## Existing central support boundary

The current `go` environment remains unchanged and `experimental`. Debian, Arch, Fedora, RHEL, openSUSE, Alpine and macOS retain their existing package-manager declarations until a separate routing decision is reviewed.

Go's documented cross-compilation targets remain distinct from supported installer hosts.

## Offline fixture coverage

The fixture uses a HOME path containing spaces and verifies:

- exact stable release selection;
- OS/architecture archive matching;
- official download URL construction;
- SHA-256 verification;
- non-mutating plan;
- sourced-helper variable namespace isolation;
- marker-bound managed verification;
- fully offline second installation;
- binary tamper rejection;
- foreign destination refusal before network;
- PATH refusal before network;
- checksum mismatch refusal;
- symlink-containing tar rejection;
- wrong-root tar rejection;
- state symlink refusal.

## Upstream references

- Go downloads: https://go.dev/dl/
- Go installation documentation: https://go.dev/doc/install
- Go release JSON: https://go.dev/dl/?mode=json

# kubectl environment

Research date: **2026-08-11**

## Support boundary

`kubectl` remains `experimental`. Adding a verified artifact adapter does **not** promote any host combination to supported status.

Current strategies remain:

- Windows: WinGet (`Kubernetes.kubectl`)
- Arch-family hosts: native package manager
- macOS: Homebrew
- Debian-family, Fedora-family, RHEL-family and openSUSE-family hosts: verified upstream binary adapter for `amd64` and `arm64`

The environment support matrix in `manifests/environments.json` remains authoritative.

## Version resolution

For the verified-binary path, `devkit-wulf` resolves the current stable kubectl version from:

`https://dl.k8s.io/release/stable.txt`

The returned value must match the strict form `vMAJOR.MINOR.PATCH`. The value is then substituted into manifest-controlled HTTPS URL templates.

The latest stable client is **not** necessarily the correct client for every cluster. Kubernetes documents a supported kubectl version skew of one minor version relative to the control plane. General cluster-aware version selection remains part of the version-resolver roadmap and must not be inferred from this adapter.

## Integrity

For Linux `amd64` and `arm64`, the adapter downloads both:

- the exact kubectl binary;
- the corresponding `.sha256` file for the same resolved version and architecture.

The local SHA-256 is compared with the upstream checksum before any installation mutation. A missing local SHA-256 implementation, malformed checksum or mismatch is a hard failure.

No checksum-bypass mode exists.

Temporary resolver and artifact files are created with `mktemp` and cleanup traps are isolated inside subshell functions so they do not replace caller cleanup handlers.

## Privilege and PATH

The verified artifact target is `/usr/local/bin/kubectl`.

The plan reports the final file operation as requiring `root-or-sudo`. Download, checksum validation, version resolution and staging remain unprivileged; elevation is scoped only to the final `install` operation.

The adapter requires `/usr/local/bin` to already exist in `PATH` and never edits PATH automatically.

## Conflict handling

Before mutation, the adapter:

1. rejects a symbolic-link destination;
2. rejects any destination that is not a regular file;
3. accepts an existing regular file only when its SHA-256 exactly matches the resolved verified artifact;
4. refuses an existing different binary and requires a future explicit upgrade/migration workflow.

A pre-existing functional kubectl discovered by the higher-level environment verification may be observed without replacement. This is intentional while explicit version/upgrade semantics remain part of the version-resolver and conflict-management roadmap.

## State tracking

The artifact state path must be safely writable **before** the host is mutated. A pre-existing `artifacts.jsonl` must be a writable regular file and must not be a symbolic link.

Verified artifact operations append metadata to `artifacts.jsonl`, including:

- environment and publisher;
- resolved version;
- binary source URL;
- checksum URL;
- destination;
- SHA-256;
- action;
- whether devkit-wulf created the destination;
- the fact that no PATH mutation occurred.

Immediately before the final host mutation, devkit-wulf records a `mutation-intent` entry containing the verified source, checksum and destination. After a successful install and installed-file hash check it records `installed-verified-artifact`. An exact existing verified artifact is recorded as `observed-exact-artifact` instead.

## Verification

After installation, the normal environment verification gate still runs:

```text
kubectl version --client
```

A successful download, checksum comparison or file copy is not treated as successful environment installation by itself.

## Upstream references

- https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/
- https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/
- https://dl.k8s.io/release/stable.txt

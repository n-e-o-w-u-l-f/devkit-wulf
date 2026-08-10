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

## Conflict handling

The verified artifact target is `/usr/local/bin/kubectl`.

The adapter:

1. requires `/usr/local/bin` to already exist in `PATH`;
2. never edits PATH automatically;
3. refuses to replace a non-regular destination;
4. accepts an existing destination only when its SHA-256 exactly matches the resolved verified artifact;
5. refuses an existing different binary and requires a future explicit upgrade/migration workflow.

This conservative behavior is intentional while GATE-08/GATE-10 ownership and migration work remains open.

## State tracking

Verified artifact operations append metadata to the devkit-wulf state directory in `artifacts.jsonl`, including:

- environment;
- resolved version;
- binary source URL;
- checksum URL;
- destination;
- SHA-256;
- action;
- whether devkit-wulf created the destination;
- the fact that no PATH mutation occurred.

## Verification

After installation, the normal environment verification gate still runs:

```text
kubectl version --client
```

A successful download or file copy is not treated as successful environment installation by itself.

## Upstream references

- https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/
- https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/
- https://dl.k8s.io/release/stable.txt

# OpenTofu environment

Research date: **2026-08-11**

## Support boundary

`opentofu` remains `experimental`. Researching or implementing an installer path does not promote any platform/environment combination to supported status.

The implementation must prefer the installation mechanism recommended for the detected host instead of forcing one method across Linux distributions.

## Current upstream strategy

### Fedora

OpenTofu 1.12 documentation states that OpenTofu is available directly from the Fedora repository.

Preferred path:

```text
dnf install opentofu
```

This is a platform-native package-manager path. Fedora therefore does not require the external OpenTofu RPM repository.

### Debian / Ubuntu / derivatives

OpenTofu publishes an official Debian repository. The documented setup uses:

- `https://get.opentofu.org/opentofu.gpg`;
- `https://packages.opentofu.org/opentofu/tofu/gpgkey`;
- `/etc/apt/keyrings/opentofu.gpg`;
- `/etc/apt/keyrings/opentofu-repo.gpg`;
- a `signed-by=` constrained source definition;
- package name `tofu`.

The second key is dearmored locally with GnuPG before use. `devkit-wulf` downloads keys before installation, uses HTTPS only, and refuses to overwrite different existing key or repository files until an explicit migration workflow exists.

### RHEL / AlmaLinux / RPM-family

The OpenTofu 1.12 RPM instructions publish an official repository at:

```text
https://packages.opentofu.org/opentofu/tofu/rpm_any/rpm_any/$basearch
```

The upstream YUM/RHEL configuration explicitly uses:

```text
gpgcheck=1
repo_gpgcheck=0
sslverify=1
```

`repo_gpgcheck=0` is therefore recorded as an upstream property for the RHEL-family target, not as a devkit-wulf verification bypass. Package signature verification remains mandatory.

### openSUSE

The official OpenTofu RPM instructions use the same package source but explicitly enable both:

```text
gpgcheck=1
repo_gpgcheck=1
sslverify=1
```

Repository refresh is performed with `zypper --gpg-auto-import-keys` for the OpenTofu binary and source repository definitions.

### Standalone releases

OpenTofu also publishes standalone release archives for Linux, macOS, Windows and BSD. Upstream provides:

- `tofu_<version>_SHA256SUMS`;
- Cosign signature and certificate files for the checksum set;
- GPG verification options.

The standalone path is intentionally not considered complete merely because a ZIP checksum can be compared. Because upstream provides cryptographic authentication for the checksum set, the future standalone adapter must verify that higher-level signature as well and must never expose the upstream skip-verification option.

## Trust-tool preflight

The vendor-repository path deliberately requires `gpg` or `gpg2` to be available **before any repository or package mutation begins**.

Although the upstream setup lists GnuPG among its prerequisites, `devkit-wulf` does not install that trust tool after downloading repository key material and then continue automatically. The downloaded OpenPGP material is parsed first, all managed destinations are conflict-checked, and only then may repository/package mutations start.

On a minimal host without GnuPG, the adapter therefore fails closed and asks the operator to establish the base/trust tooling first. This preserves the GATE-04/GATE-05/GATE-08 ordering rather than weakening it for convenience.

## Repository adapter safety contract

The vendor-repository helper introduced for this environment follows these rules:

1. all documentation, package and key origins are manifest-controlled;
2. key URLs must use HTTPS;
3. downloaded OpenPGP key material must parse successfully before host mutation;
4. all managed key/repository destinations are conflict-checked before prerequisite/package mutation;
5. repository configuration is written from exact manifest content, not assembled from user-controlled shell fragments;
6. existing different repository/key files are conflicts and are not overwritten;
7. symlink destinations and repository-state symlinks are rejected;
8. repository state records mutation intent and post-mutation results;
9. package signatures remain enabled;
10. TLS verification remains enabled;
11. no `--skip-verify`, insecure TLS option or generic trust bypass is introduced;
12. environment verification still requires `tofu -version` after package installation.

## Strategy resolution

The environment catalog still records `manual` for OpenTofu combinations that were previously unautomated. The POSIX CLI now resolves an **effective strategy** only when a matching, schema-validated entry exists in `manifests/repositories.json`.

This keeps the distinction visible:

```text
declared_strategy=manual
strategy=vendor-repository
```

or, for Fedora:

```text
declared_strategy=manual
strategy=package-manager
```

The support state is not changed by this resolution and remains `experimental`.

Current effective Linux resolution:

- Fedora -> `package-manager` using native package `opentofu`;
- Debian family -> `vendor-repository` using APT and package `tofu`;
- RHEL family -> `vendor-repository` using DNF and package `tofu`;
- openSUSE family -> `vendor-repository` using Zypper and package `tofu`;
- other OpenTofu paths retain their previously declared strategy and remain fail-closed unless a verified adapter already exists.

`plan` shows the effective strategy, repository source, key sources, package manager, package, required privilege, signature policy and conflict policy without mutating the host.

## Validation status

The branch includes:

- repository JSON Schema validation;
- cross-manifest semantic policy validation;
- isolated no-network/no-root repository helper tests;
- conflict-before-mutation assertions;
- state-file and state-directory symlink refusal tests;
- portable CLI strategy-resolution checks;
- ShellCheck/security-scan inclusion through the existing `lib/*.sh` CI scope.

Hosted GitHub Actions remain subject to the repository account's external runner/billing availability. A successful fixture test does not promote support by itself.

## Upstream references

- https://opentofu.org/docs/v1.12/intro/install/
- https://opentofu.org/docs/v1.12/intro/install/deb/
- https://opentofu.org/docs/v1.12/intro/install/fedora/
- https://opentofu.org/docs/v1.12/intro/install/rpm/
- https://opentofu.org/docs/v1.12/intro/install/standalone/
- https://github.com/opentofu/opentofu/releases

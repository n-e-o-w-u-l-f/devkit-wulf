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

The second key is dearmored locally with GnuPG before use. `devkit-wulf` must download keys before installation, use HTTPS only, and refuse to overwrite different existing key or repository files until an explicit migration workflow exists.

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

## Repository adapter safety contract

The vendor-repository helper introduced for this environment follows these rules:

1. all documentation, package and key origins are manifest-controlled;
2. key URLs must use HTTPS;
3. repository configuration is written from exact manifest content, not assembled from user-controlled shell fragments;
4. existing different repository/key files are conflicts and are not overwritten;
5. symlink destinations are rejected;
6. repository state is recorded before and after owned mutations;
7. package signatures remain enabled;
8. TLS verification remains enabled;
9. no `--skip-verify`, insecure TLS option or generic trust bypass is introduced;
10. environment verification still requires `tofu -version` after package installation.

## Current integration status

This branch adds the repository catalog, schema, helper layer and isolated tests. CLI strategy promotion/wiring is a separate gate: until the CLI explicitly selects these adapters and the corresponding tests pass, the existing environment manifest remains authoritative and fail-closed behavior is preserved.

## Upstream references

- https://opentofu.org/docs/v1.12/intro/install/
- https://opentofu.org/docs/v1.12/intro/install/deb/
- https://opentofu.org/docs/v1.12/intro/install/fedora/
- https://opentofu.org/docs/v1.12/intro/install/rpm/
- https://opentofu.org/docs/v1.12/intro/install/standalone/
- https://github.com/opentofu/opentofu/releases

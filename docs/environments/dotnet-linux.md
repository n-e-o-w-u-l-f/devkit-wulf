# .NET 10 Linux adapter

Status: **experimental**

This adapter implements only host/version/package-source combinations that were revalidated against current upstream documentation on 2026-08-11. Package-manager compatibility does not imply support.

## Active matrix

| Platform | Versions | Package source | Package manager | Architectures enabled by this adapter |
|---|---|---|---|---|
| Debian | 12, 13 | Microsoft Production repository | APT | amd64, arm64 |
| Fedora | 43, 44 | Fedora repositories | DNF | amd64 |
| RHEL | 8, 9, 10 | RHEL AppStream | DNF | amd64, arm64, s390x, ppc64le |
| openSUSE Leap | 16 | Microsoft Production repository | Zypper | amd64, arm64 |

The SDK package is `dotnet-sdk-10.0` on every active target.

Fedora arm64 is intentionally not activated by this contract yet. Additional architectures require explicit package-target evidence before activation.

## Microsoft repository trust

Debian and openSUSE Leap use `packages.microsoft.com`, but their repository setup is intentionally different.

### Debian 12/13

The adapter constructs a minimal deterministic APT source after validating Microsoft's OpenPGP signing key fingerprint. The APT source uses an explicit `signed-by=` keyring.

Debian repository suites are pinned to:

- Debian 12 → `bookworm`
- Debian 13 → `trixie`

APT key handling is explicit:

- Debian 12: `microsoft.asc`, dearmored into `/usr/share/keyrings/microsoft-prod.gpg`
- Debian 13: `microsoft-2025.asc`, dearmored into `/usr/share/keyrings/microsoft-prod.gpg`

### openSUSE Leap 16

Microsoft's current documentation explicitly downloads:

`https://packages.microsoft.com/config/opensuse/16/prod.repo`

The adapter therefore downloads that official, non-executable repository file rather than synthesizing a Zypper repository format. Before installation it verifies that the file:

- is non-empty,
- contains the expected `https://packages.microsoft.com/opensuse/16/prod/` base URL,
- contains the expected `packages-microsoft-com-prod` repository id,
- does not explicitly disable GPG, repository-metadata, or TLS verification.

The Microsoft ASCII signing key is fingerprint-validated before being installed and imported by RPM. The key is not dearmored for this path because Microsoft's openSUSE instructions import `microsoft.asc` directly.

Microsoft also documents `libicu` as a prerequisite in the Leap setup. The adapter installs that package through Zypper before the .NET SDK package after repository/key conflict checks have passed.

## Pinned Microsoft keys

- Debian 12 and openSUSE Leap 16: `microsoft.asc` — `BC52 8686 B50D 79E3 39D3 721C EB3E 94AD BE12 29CF`
- Debian 13: `microsoft-2025.asc` — `AA86 F75E 427A 19DD 3334 6403 EE4D 7792 F748 182B`

Microsoft documents signing of packages and repository metadata. The adapter never disables TLS verification or signature checking.

## Distribution-owned packages

Fedora and RHEL do not receive a Microsoft repository from this adapter.

Fedora installs `dotnet-sdk-10.0` from Fedora's repositories for Fedora 43/44.

RHEL installs `dotnet-sdk-10.0` from AppStream for RHEL 8/9/10. A registered RHEL host is required; the adapter checks `subscription-manager identity` before package mutation.

## Gates

Before mutation, the adapter requires:

1. exact platform ID,
2. exact supported distribution version,
3. exact enabled architecture,
4. expected package manager,
5. expected package source,
6. GnuPG before Microsoft-repository mutation,
7. exact Microsoft key fingerprint,
8. expected official repository source/content where a repository file is downloaded,
9. no symlink or conflicting existing repository/key file,
10. writable non-symlink state storage,
11. explicit experimental opt-in through the top-level CLI.

Existing .NET 10 SDK installations are observed but not claimed as devkit-owned.

## Verification

A completed installation must satisfy:

```sh
dotnet --info
dotnet --list-sdks
```

At least one SDK version beginning with `10.` must be present. On the exact Linux adapter targets, the top-level `verify dotnet` path uses this 10.x check rather than accepting an arbitrary older SDK.

## Non-inheritance

The following are deliberately **not** inferred:

- Linux Mint from Debian,
- Ubuntu from Debian,
- Rocky Linux or AlmaLinux from RHEL,
- CentOS Stream from RHEL,
- openSUSE Tumbleweed from Leap,
- another Fedora-family distribution from Fedora.

Each requires its own exact target contract.

## Sources

- Microsoft Learn: Debian .NET installation
- Microsoft Learn: Fedora .NET installation
- Microsoft Learn: RHEL and CentOS Stream .NET installation
- Microsoft Learn: openSUSE Leap .NET installation
- Microsoft Linux package repository signing-key documentation
- Fedora package catalog for `dotnet-sdk-10.0`
- Red Hat .NET life-cycle / architecture policy

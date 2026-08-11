# Docker environment

Research date: **2026-08-11**

## Support boundary

`docker` remains `experimental`. Adding repository or native-package adapters does not promote any platform/environment combination to supported status.

Docker Desktop and Docker Engine are separate installation domains in `devkit-wulf`:

- Windows and macOS continue to use the existing Desktop-oriented paths where applicable;
- Linux Engine installation prefers an explicitly researched native or vendor-repository path;
- Docker Desktop on Linux is not substituted for the native Engine path.

## Exact vendor-platform policy

The Docker Engine vendor-repository adapter is intentionally **platform-specific**, not Linux-family-wide.

Current exact Docker-vendor targets:

- Debian;
- Ubuntu;
- Fedora;
- RHEL.

A derivative does not inherit one of these targets merely because it uses APT, DNF, or a compatible package format. For example, Linux Mint remains on the previously declared `manual` path rather than silently inheriting the Ubuntu repository contract. Rocky Linux and AlmaLinux likewise do not inherit the RHEL target through package compatibility alone.

This distinction is deliberate: availability of packages is not equivalent to an upstream support claim.

## Debian

The Docker Engine Debian adapter follows the official Docker APT-repository layout.

Current researched gate:

- Debian 11, 12, 13;
- `amd64`, `armv7`/armhf, `arm64`, `ppc64le`;
- key: `https://download.docker.com/linux/debian/gpg`;
- key destination: `/etc/apt/keyrings/docker.asc`;
- repository file: `/etc/apt/sources.list.d/docker.sources`;
- suite: detected `VERSION_CODENAME`;
- architecture: `dpkg --print-architecture`.

Packages:

```text
docker-ce
docker-ce-cli
containerd.io
docker-buildx-plugin
docker-compose-plugin
```

Conflicting packages are detected before mutation. `devkit-wulf` does not automatically remove them.

## Ubuntu

The Ubuntu adapter uses the separate Docker Ubuntu repository and the same five Engine packages.

Current researched version gate:

- Ubuntu 22.04 LTS;
- Ubuntu 24.04 LTS;
- Ubuntu 25.10;
- Ubuntu 26.04 LTS.

Current architecture gate:

- `amd64`;
- `armv7`/armhf;
- `arm64`;
- `ppc64le`;
- `s390x`.

The repository suite is resolved from `UBUNTU_CODENAME` with `VERSION_CODENAME` as the documented-compatible fallback. The adapter refuses unsafe suite or architecture tokens before writing repository configuration.

Docker's own Ubuntu documentation warns that derivative distributions such as Linux Mint are not officially supported. `devkit-wulf` therefore does not silently reuse the Ubuntu vendor contract for Mint.

## Fedora

Current researched vendor target:

- Fedora 43 and 44;
- `amd64`, `arm64`, `ppc64le`.

The adapter downloads the official repository definition from Docker rather than constructing it from arbitrary shell fragments:

```text
https://download.docker.com/linux/fedora/docker-ce.repo
```

The downloaded repository file must contain the expected package-signature configuration and Docker GPG-key URL before it can be installed.

The Docker signing key is downloaded separately and parsed with GnuPG. Its fingerprint must match the Docker-documented value:

```text
060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35
```

A fingerprint mismatch hard-fails before repository or package mutation.

After package installation, the declared service action is:

```text
systemctl enable --now docker
```

## RHEL

Current researched vendor target:

- RHEL 8, 9, 10;
- `amd64`, `arm64`, `s390x`.

Repository definition:

```text
https://download.docker.com/linux/rhel/docker-ce.repo
```

The same Docker signing-key fingerprint is required as for Fedora. RHEL conflict packages, including `podman` and `runc`, are detected and reported. They are **not** removed automatically; an explicit migration/removal decision is required.

The post-install service action is:

```text
systemctl enable --now docker
```

## CentOS, Rocky Linux, AlmaLinux and other RPM derivatives

Package-format compatibility is not treated as an automatic Docker support contract.

The host detector no longer collapses CentOS into `rhel`. This prevents the exact RHEL Docker vendor target from being selected for a CentOS host merely because both use RPM tooling.

Rocky Linux and AlmaLinux already have distinct platform IDs and remain on their declared non-vendor path until a separate current upstream contract is researched and encoded.

## openSUSE

Docker's Engine tested-platform documentation does not use openSUSE as the same vendor-repository target modeled for Debian/Ubuntu/Fedora/RHEL.

For openSUSE Leap and Tumbleweed, `devkit-wulf` instead records the distribution-native `docker` package from openSUSE documentation. This is modeled as a native-package override, not a Docker vendor repository.

The native openSUSE path declares:

```text
zypper install docker
systemctl enable --now docker
```

The service action remains explicitly tracked as a host mutation.

## Conflict gate

Before any repository key, repository file, prerequisite, Docker package, or service mutation, the adapter checks the target's known conflicting package list using the platform-native package database.

If a conflict is installed:

- installation stops;
- no automatic package removal occurs;
- the conflicting package names are reported;
- the operator must choose an explicit migration/removal path later.

This prevents an environment install request from silently replacing another container stack.

## Repository trust gate

Vendor repository setup follows this sequence:

1. resolve the exact platform target;
2. validate OS version and architecture where the target declares them;
3. preflight known package conflicts;
4. require service-management capability if a service action is declared;
5. download repository keys over HTTPS;
6. parse OpenPGP key material with GnuPG;
7. compare any declared expected fingerprint;
8. stage the repository configuration;
9. require declared security markers for remotely supplied `.repo` files;
10. reject package-signature or TLS-disable directives;
11. conflict-check every managed destination;
12. only then begin host mutation and state logging.

Existing different key or repository files are not overwritten automatically.

## Plan behavior

`plan docker` remains non-mutating and reports:

- detected platform, version, architecture and package manager;
- declared vs effective strategy;
- target scope (`platform:<id>` or family fallback where applicable);
- packages and prerequisites;
- known conflicting packages;
- repository/key sources;
- expected key fingerprint where defined;
- package/repository signature policy;
- TLS policy;
- service actions;
- conflict policy.

## Verification

The existing environment verification remains:

```text
docker version
```

A package-manager success alone is not considered proof of a functional Docker environment.

Daemon/runtime smoke testing beyond the client/server version check should be added only where the CI/target environment can safely run Docker Engine. The support state remains `experimental` until the required target validation gates pass.

## Removal

Safe removal ownership is not yet established. `devkit-wulf remove docker` therefore remains fail-closed under GATE-15.

Docker data directories and user workloads are not to be deleted as an incidental consequence of package removal.

## Upstream references

- Docker Engine installation overview: https://docs.docker.com/engine/install/
- Debian: https://docs.docker.com/engine/install/debian/
- Ubuntu: https://docs.docker.com/engine/install/ubuntu/
- Fedora: https://docs.docker.com/engine/install/fedora/
- RHEL: https://docs.docker.com/engine/install/rhel/
- openSUSE Docker documentation: https://en.opensuse.org/Docker

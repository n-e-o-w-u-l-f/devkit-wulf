# .NET Linux research gate

Research date: **2026-08-11**

## Purpose

This document records the next-stage `.NET` Linux work without activating any new installer path prematurely.

The repository already models `.NET` as an experimental environment. The new research contract intentionally keeps:

```text
activation: false
status: research-only
```

until each exact platform/version/architecture/package-source combination is revalidated against current Microsoft documentation.

## Exact platform scopes

The research contract tracks Microsoft documentation separately for:

- Debian;
- Fedora;
- RHEL;
- openSUSE Leap.

The target scope is intentionally `platform`, not a generic package-manager family.

A Debian derivative does not inherit Debian support automatically. An RPM-compatible distribution does not inherit RHEL or Fedora support automatically. Package-manager compatibility is not a support claim.

## Why activation remains blocked

Before a `.NET` Linux adapter becomes executable, the implementation must encode and test:

1. exact currently supported distribution versions;
2. .NET major/LTS availability by distribution version;
3. architecture support by distribution/version/source;
4. whether packages are owned by the distribution or Microsoft feed;
5. repository-key/signing behavior where a Microsoft feed is used;
6. current package identifiers;
7. non-mutating plan output;
8. idempotent install and verification on the exact target;
9. known or fail-closed removal ownership.

This prevents a stale version matrix from being embedded merely because an `apt`, `dnf` or `zypper` command appears syntactically valid.

## Source policy

Only current Microsoft `.NET` installation documentation is accepted as the activation source for this contract:

- `https://learn.microsoft.com/en-us/dotnet/core/install/linux-debian`
- `https://learn.microsoft.com/en-us/dotnet/core/install/linux-fedora`
- `https://learn.microsoft.com/en-us/dotnet/core/install/linux-rhel`
- `https://learn.microsoft.com/en-us/dotnet/core/install/linux-opensuse`

The machine-readable manifest records these source pages but deliberately does not freeze package/version claims that have not yet been encoded with their exact current matrices.

## Relation to Issue #2

This is a preparatory part of the `.NET distribution-specific repositories/archive paths` work.

It creates a fail-closed contract that can be populated incrementally without modifying the active package/repository adapters until the required source, version, architecture and signing data are complete.

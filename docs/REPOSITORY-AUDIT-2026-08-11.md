# Repository audit — 2026-08-11

This document records the ReadmeGPT audit snapshot for `n-e-o-w-u-l-f/devkit-wulf` after reviewing the repository structure, governance, documentation, manifests, workflows, recent implementation history and repository metadata.

## Executive status

`devkit-wulf` is a pre-1.0, manifest-driven, multi-platform developer-environment orchestrator with a strong fail-closed security model. The implementation is materially ahead of the previous roadmap/changelog snapshot: several concrete versioned environments now have system-native or verified-artifact contracts, dedicated adapters, offline fixtures, validation and CI.

The repository is **not yet at stable-release Sollzustand**. The main remaining gap is no longer initial scaffolding; it is promotion-quality evidence and operational completeness across the advertised matrix.

## Iststand

### Governance and architecture

- `AGENTS.md` defines GATE-00 through GATE-19 and a clear separation of detection, support resolution, installation strategy, verification, state and rollback.
- Release-facing execution is organized around system-native installer families rather than a misleading universal executable.
- Unsupported or unverified combinations are expected to fail closed.

### Platforms

Primary implementation targets include Windows, WSL2, mainstream Linux families and macOS. BSD, illumos, Solaris and AIX are represented as research/validation targets and remain gated until authoritative target validation exists.

### Environment catalogue

The repository models core developer tooling, language runtimes/toolchains, editors/IDEs, mobile stacks, containers and infrastructure tools. Profiles compose these environments without automatically promoting experimental combinations.

### Concrete implementation progress

Recent merged work demonstrates that the repository has advanced beyond generic package-manager execution:

- Python 3.12: system-native routing across Linux, WSL, macOS and Windows;
- Go stable: system-native Linux/WSL/macOS routes plus verified native Windows artifact installation;
- Rust stable: system-native Linux/WSL/macOS routes plus verified native Windows `rustup-init` artifact installation;
- Flutter stable: system-native Linux/macOS/Windows routing with managed verification and explicit fail-closed WSL behavior;
- kubectl stable: native Windows and macOS verified-artifact contracts;
- dedicated contract validation, offline fixtures and GitHub Actions coverage for these paths;
- additional workflow/manifest work for installer families, .NET/Linux research, PHP/Composer and JetBrains Toolbox.

### Documentation

Present:

- canonical English README;
- German, French, Polish, Simplified Chinese, Russian and Spanish README translations;
- translation policy;
- roadmap;
- changelog;
- contributing, support and security policies;
- installer-architecture and platform-strategy documentation;
- environment-specific documentation tree;
- primary-source research tree.

The previous `ROADMAP.md` and `CHANGELOG.md` lagged behind implementation work merged on 2026-08-11. This audit branch synchronizes those documents with the observed implementation state.

### Repository metadata

- Public repository;
- default branch: `main`;
- primary language reported by GitHub: Shell;
- description is present and accurately summarizes the multi-platform scope;
- GitHub detects the MIT license;
- repository topics are currently empty;
- Issues and Wiki are enabled;
- Discussions are disabled;
- no homepage is configured.

### Licensing

The repository contains a standard MIT license and GitHub detects SPDX identifier `MIT`. The audit does not change the license choice.

A separate compliance question remains: repository-wide SPDX/REUSE metadata is not currently present. If REUSE compliance is adopted as a project requirement, file-level copyright/licensing metadata and corresponding validation should be introduced deliberately and consistently rather than inferred from the top-level license alone.

## Sollstand

The target state is a stable-release-capable repository whose support claims are mechanically tied to evidence.

### P0 — release blockers

1. Required CI must execute and pass for every combination intended to be promoted.
2. Promotion states in manifests must reflect tested reality rather than implementation existence.
3. Ownership-aware removal/rollback must exist for every environment advertised as safely removable.
4. Integrity/signature validation must be exercised by tests for verified artifact paths.
5. Release checksum generation and SBOM generation must be implemented and documented.
6. No unresolved critical security finding may remain at release time.
7. Changelog, roadmap, README and translations must match the release support matrix.

### P1 — repository completeness

1. Keep a single evidence-backed status source for environment/platform promotion.
2. Ensure every executable route has environment documentation, verification behavior, limitations and upstream provenance.
3. Add GitHub topics reflecting the actual scope, for example: `developer-tools`, `bootstrap`, `dev-environment`, `windows`, `wsl2`, `linux`, `macos`, `bsd`, `powershell`, `shell`, `python`, `golang`, `rust`, `flutter`, `kubectl`, `devops`.
4. Decide whether repository-wide REUSE compliance is a goal; if yes, implement it as an explicit metadata/CI change without changing the MIT licensing decision.
5. Keep translation synchronization gated whenever canonical README semantics change.
6. Define release/version provenance so pre-1.0 development, tags and changelog entries cannot drift.

### P2 — quality and discoverability

1. Add stable, evidence-backed status badges only after corresponding workflows are authoritative.
2. Add a concise implementation-status table to the canonical README when support promotion data can be generated reliably from manifests.
3. Consider a project homepage only if a maintained documentation or release landing page exists.
4. Enable Discussions only if the project intends to support community Q&A outside Issues.

## Changes made by this audit

On branch `readmegpt/audit-2026-08-11`:

- synchronized `CHANGELOG.md` with the implementation work visible in current manifests/workflows/recent merges;
- refreshed `ROADMAP.md` to status date 2026-08-11 and separated implemented mechanics from remaining promotion gates;
- added this evidence-oriented repository audit document.

No runtime installer/security code, support-state promotion, repository license choice or unverified support claim was changed.

## Remaining external repository-setting actions

The connected repository interface used for this audit does not expose a repository-settings mutation for topics/homepage/discussions. Those settings therefore remain documented Soll actions rather than silently modified repository state.

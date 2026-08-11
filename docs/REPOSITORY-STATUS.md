# Repository status

Status date: **2026-08-11**

This document records the audited current state of `devkit-wulf` and the conditions required for the intended state. It is descriptive, not a support-promotion mechanism. `AGENTS.md` remains authoritative for GATE-00 through GATE-19.

## Executive status

`devkit-wulf` has progressed beyond its original orchestration scaffold into a substantial pre-1.0, contract-driven multi-platform installer framework. The repository contains host detection, platform/environment manifests, package-manager and vendor-repository helpers, verified artifact transactions, system-native release entrypoints, offline fixtures, semantic validators, and security-oriented CI definitions.

No environment/platform combination is promoted merely because an adapter exists. Current executable lanes remain experimental or explicitly unsupported until their complete gate set is satisfied.

## Current implementation boundary

### Generic orchestration

The generic POSIX and PowerShell cores provide detection, listing, planning, installation, verification, profile handling, state recording, conflict checks, and fail-closed removal entrypoints. Two roadmap-level CLI capabilities are not yet implemented:

- explicit version resolution through `--version`;
- explicit execution-domain selection through `--target native|wsl:<distro>`.

Safe removal is also not complete. The cores refuse removal when ownership cannot be proven and currently have no complete product-specific removal adapter path.

### System-native versioned selectors

The release-facing `installers/` boundary currently contains dedicated selector routes and adapters for:

| Selector | Linux | WSL2 | macOS | Windows | Notes |
| --- | --- | --- | --- | --- | --- |
| `python@3.12` | experimental | experimental | experimental | experimental | system-native adapters present |
| `go@stable` | experimental | experimental | experimental | experimental | Windows route is active; workflow reconciliation remains open |
| `rust@stable` | experimental | experimental | experimental | staged, not centrally routed | Windows native adapter/manifest exists but the release selector remains gated |
| `flutter@stable` | experimental | unsupported | experimental | experimental | verified archive path; WSL intentionally blocked |
| `kubectl@stable` | not centrally routed | not centrally routed | direct experimental adapter | direct experimental adapter | native adapter work exists without a shared release-selector promotion |

The unversioned generic environment catalog remains separate from these versioned release selectors.

### Additional reviewed component work

The repository also contains reviewed implementation and validation layers for, among others:

- Windows PHP runtime plus Composer orchestration;
- Linux .NET repository/package contracts;
- verified JetBrains Toolbox artifacts;
- verified repository configuration and key-fingerprint handling;
- generic verified artifact helpers;
- Docker/repository research contracts;
- extended-platform detection and bootstrap paths.

Presence of these components does not broaden support beyond the explicit manifest state.

## Security and integrity posture

Implemented mechanisms include:

- HTTPS-only source policies and approved-host checks where applicable;
- SHA-256 or release-metadata integrity validation for reviewed artifact paths;
- repository-key fingerprint checks;
- staged downloads before mutation;
- archive traversal/symlink/reparse-point defenses;
- refusal to adopt foreign/unowned destinations;
- explicit experimental opt-in before mutation for versioned selectors;
- no implicit persistent PATH mutation in reviewed artifact adapters;
- unprivileged user-local destinations where the reviewed contract permits them;
- ownership markers and critical-file hashes;
- offline/idempotent second-install fixtures for reviewed artifact paths;
- security scanning for stream execution, verification bypasses, destructive disk commands, and related unsafe patterns.

These controls do not replace GATE-15 ownership-aware removal or GATE-19 release requirements.

## Validation status

The repository contains extensive offline Shell/PowerShell fixtures and Python semantic validators. The full `tests/` tree was audited on 2026-08-11.

GitHub-hosted CI is **not currently authoritative**: the latest examined Actions run was prevented from starting by an account/billing infrastructure condition. A workflow that never received a runner is neither a passing nor a failing product test.

Two static contract inconsistencies were identified independently of hosted CI:

1. **Environment ID drift — issue #34.** The canonical catalog defines `xcode`, while the `mobile`/`full` profiles and `tests/validate_manifests.py` still reference `apple`.
2. **Go Windows workflow drift — issue #35.** The shared `go@stable` validator requires the active native Windows route, while `.github/workflows/go-stable-system-native.yml` still contains the obsolete assertion that Windows must reject `go@stable`.

These must be reconciled before CI can be treated as a meaningful promotion signal.

## Documentation status

The audit found documentation lag in several areas: the changelog did not reflect the 2026-08-11 implementation wave, the roadmap described several implemented artifact paths as future work, some component documents described active routing as pending, and the translated READMEs still exposed the older `bin/`-centric boundary.

The ReadmeGPT reconciliation branch now updates:

- canonical `README.md`;
- all maintained README translations (German, French, Polish, Simplified Chinese, Russian and Spanish);
- `ROADMAP.md` and `CHANGELOG.md`;
- `environments/README.md` and `installers/README.md`;
- installer architecture and affected environment-component documentation;
- this canonical repository-state snapshot.

All maintained README translations on this branch now describe the same release-facing `installers/` boundary, canonical `xcode` environment ID, selector-routing state, CI limitation, and pre-1.0 support boundary as the English README. Future material README changes must continue to follow `docs/TRANSLATIONS.md`.

## GitHub and release state

As of 2026-08-11:

- default branch: `main`;
- license: MIT;
- GitHub Releases: none;
- Git tags: none;
- repository topics: none configured at audit time;
- homepage metadata: not configured at audit time;
- branch-protection details: not readable through the connected integration and therefore treated as unknown.

No stable-release claim is justified while the release gate remains open.

## Open target-state gates

The following existing issues remain the principal roadmap blockers:

- **#3 — conflict detection, ownership/rollback, and safe uninstall**;
- **#4 — version resolver and explicit native/WSL target selection**;
- **#5 — authoritative BSD/illumos/Solaris/AIX validation**;
- **#6 — release gate, checksums, and SBOM**.

The audit added:

- **#34 — reconcile `apple`/`xcode` environment IDs**;
- **#35 — align Go stable Windows CI with the active route**.

## Desired state

The repository reaches the intended state only when all claimed support is evidence-backed rather than inferred from file presence. At minimum:

1. machine-readable catalogs, profiles, validators, adapters, workflows, and documentation agree;
2. version and execution-domain selection are explicit and deterministic;
3. conflict detection and ownership-aware removal are complete for any safely removable environment;
4. every promoted host/environment pair has authoritative target validation, verification, idempotency, and removal evidence;
5. GitHub Actions can run and all required checks pass after the known static workflow/manifest inconsistencies are fixed;
6. release artifacts have reproducible checksums and an SBOM;
7. documentation and translations match the promoted support matrix;
8. support promotion is a distinct reviewed change after all required gates pass.

Until then, `experimental` and `unsupported` remain the correct public support states.

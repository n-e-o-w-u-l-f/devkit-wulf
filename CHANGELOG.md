# Changelog

All notable changes to `devkit-wulf` are documented here.

The project follows semantic versioning once a stable public release line is established. Until a release/tag exists, entries under **Unreleased** describe repository implementation only and do not imply promoted support.

## [Unreleased]

### Added

- Repository governance contract and mandatory GATE-00 through GATE-19 lifecycle.
- Manifest-driven platform, environment, profile, repository, artifact and installer-family models.
- Multi-platform bootstrap architecture for Windows, Linux, WSL, macOS, BSD, Solaris/illumos and AIX families.
- Windows PowerShell and POSIX generic orchestration cores with detect/list/plan/install/verify/remove/doctor flows.
- System-native release-facing entrypoints under `installers/`.
- Profiles for minimal, web, backend, systems, mobile, DevOps and full setups.
- Dated primary-source research baseline and fail-closed research contracts.
- Security scanning, manifest validation, offline fixture testing and idempotency scaffolding.
- Verified repository helper mechanics with HTTPS, key-fingerprint, conflict and state checks.
- Verified artifact helper mechanics with staged download, SHA-256 validation, archive safety, ownership markers and critical-file hashes.
- `python@3.12` experimental system-native contracts/adapters for Linux, WSL2, macOS and Windows.
- `go@stable` experimental verified-artifact contracts/adapters for Linux, WSL2, macOS and Windows.
- `rust@stable` experimental verified rustup-artifact contracts/adapters for Linux, WSL2 and macOS.
- Staged native Windows rustup manifest/helper/adapter and offline validation; the central Windows `rust@stable` release route remains intentionally gated.
- `flutter@stable` experimental verified archive contracts/adapters for Linux, macOS and Windows; WSL remains explicitly unsupported for this selector.
- Direct experimental native kubectl artifact adapters for macOS and Windows, without a promoted shared `kubectl@stable` release selector.
- Windows PHP runtime plus Composer orchestration and verification.
- Linux .NET repository/package contracts for selected distributions.
- Verified JetBrains Toolbox artifact handling and validation.
- Canonical repository-state snapshot at `docs/REPOSITORY-STATUS.md`.

### Changed

- Release-facing documentation now distinguishes the generic `bin/` orchestration cores from the system-native `installers/` boundary.
- Roadmap language now separates implemented product-specific artifact lanes from still-open generic/release gates.
- Documentation explicitly distinguishes staged adapters from centrally routed selectors and from promoted support.
- English, German, French, Polish, Simplified Chinese, Russian and Spanish READMEs are synchronized to the same 2026-08-11 release boundary, canonical `xcode` ID, selector-routing matrix, CI limitation and pre-1.0 support policy.

### Known issues / gates

- Safe ownership-aware removal remains incomplete; see issue #3.
- Generic version resolution and explicit native/WSL target selection remain open; see issue #4.
- BSD/illumos/Solaris/AIX authoritative target validation remains open; see issue #5.
- Release checksums/SBOM and stable release gating remain open; see issue #6.
- `profiles/profiles.json` and `tests/validate_manifests.py` still reference `apple` while the canonical environment ID is `xcode`; see issue #34.
- The Go stable workflow still contains an obsolete Windows fail-closed assertion although the native Windows route is active; see issue #35.
- GitHub-hosted Actions were blocked before runner start by an external account/billing condition at the 2026-08-11 audit point; hosted CI is therefore not recorded as passing or failing product validation.

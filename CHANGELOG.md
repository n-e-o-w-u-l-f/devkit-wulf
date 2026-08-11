# Changelog

All notable changes to `devkit-wulf` are documented here.

The project follows semantic versioning once a stable public release line is established.

## [Unreleased]

### Added

- Repository governance contract and mandatory gates.
- Manifest-driven platform/environment model.
- Initial multi-platform bootstrap architecture.
- Windows PowerShell and POSIX CLI targets.
- Profiles for minimal, web, backend, systems, mobile, DevOps and full setups.
- Dated primary-source research baseline.
- CI, manifest, security and idempotency validation scaffolding.
- System-native Python 3.12 contracts, adapters and entrypoint routing for Linux, WSL, macOS and Windows, including cross-adapter validation and CI coverage.
- System-native Go stable contracts and adapters for Linux, WSL and macOS, plus a verified native Windows artifact path with offline fixtures and contract validation.
- System-native Rust stable contracts and adapters for Linux, WSL and macOS, plus a verified native Windows `rustup-init` artifact path with offline fixtures and CI validation.
- System-native Flutter stable routing for Linux, macOS and Windows with managed verification, offline fixtures and fail-closed WSL handling.
- Native kubectl stable artifact contracts for Windows and macOS with verified helpers, offline fixtures, contract validation and CI coverage.
- Installer-family manifests and dedicated environment/artifact manifests for version- and platform-specific execution paths.
- Dedicated GitHub Actions workflows for system-native Python, Go, Rust, Flutter, kubectl, .NET, PHP/Composer, JetBrains Toolbox and installer-family validation.

### Changed

- Release-facing execution is increasingly routed through system-native installer entrypoints rather than the generic orchestration core.
- Stable selectors for implemented environments now preserve explicit platform/domain gates and fail closed when a verified route is unavailable.
- Documentation now distinguishes implemented mechanics from promoted support and treats CI/target validation as a separate promotion gate.

### Security

- Verified artifact paths retain explicit provenance and integrity contracts instead of falling back to unverified downloads.
- Offline fixtures and contract-validation workflows exercise fail-closed behavior without requiring production downloads during tests.

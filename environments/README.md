# Shared environment contracts

This directory contains version-specific, platform-neutral environment intent.

A shared contract describes **what** should exist after installation: selector/version or release channel, components, verification semantics, adapter inventory, and common security policy. It must not pretend that host-specific package managers, executable formats, privilege mechanics, filesystem rules, or archive transactions are interchangeable.

System-native implementations belong under `installers/<family>/environments/`.

## Current layout

The versioned contract model is active, not a future-only placeholder. Current examples include:

```text
environments/python/3.12.json
environments/go/stable.json
environments/rust/stable.json
environments/flutter/stable.json
```

Their reviewed system-native implementations are split by execution domain, for example:

```text
installers/linux/environments/python-3.12.sh
installers/wsl/environments/python-3.12.sh
installers/macos/environments/python-3.12.sh
installers/windows/environments/python-3.12.ps1
```

The same pattern is used where a selector has independently reviewed Go, Rust, Flutter, or other host-native adapters.

## Contract versus routing versus support

These are three different states:

1. **Contract exists** — shared intent and policy are machine-readable.
2. **Adapter/routing exists** — one or more release-facing system entrypoints can resolve that selector.
3. **Support is promoted** — all required governance gates and authoritative target evidence have passed.

A contract or adapter never promotes support by itself.

Examples from the 2026-08-11 audited state:

- `go@stable` is experimentally routed on Linux, WSL2, macOS, and Windows;
- a native Windows `rust@stable` adapter/manifest exists, but the top-level Windows release selector still gates it;
- native macOS/Windows kubectl adapters exist without a promoted shared `kubectl@stable` selector.

Every environment/platform/version combination still requires the normal support, source, integrity, conflict, plan, verification, idempotency, removal, CI, documentation, and release gates.

See `docs/installer-architecture.md` and `docs/REPOSITORY-STATUS.md`.

# Shared environment contracts

This directory is reserved for version-specific, platform-neutral environment intent.

A shared contract describes **what** should exist after installation (version/channel, components, verification semantics and common security policy). It must not embed host-specific package-manager commands, Windows installer assumptions, Linux filesystem assumptions or platform-specific privilege mechanics.

System-native implementations belong under `installers/<family>/environments/` as they are researched and implemented.

Example future layout:

```text
environments/python/3.12.json
installers/windows/environments/python-3.12.ps1
installers/linux/environments/python-3.12.sh
installers/macos/environments/python-3.12.sh
```

A shared environment contract does not activate support by itself. Every environment/platform/version combination still requires the normal support, source, integrity, conflict, plan, verification, idempotency and CI gates.

See `docs/installer-architecture.md`.

# System-native installer entrypoints

Use the entrypoint that matches the operating-system/domain in which the developer tools will actually run.

```text
Windows native     installers/windows/devkit-wulf.ps1
Linux native       installers/linux/devkit-wulf.sh
WSL2 Linux         installers/wsl/devkit-wulf.sh
macOS              installers/macos/devkit-wulf.sh
BSD family         installers/bsd/devkit-wulf.sh
Solaris / illumos  installers/solaris/devkit-wulf.sh
AIX                installers/aix/devkit-wulf.sh
```

Each entrypoint fails closed when executed on the wrong host family. WSL2 is deliberately distinct from native Linux even though both use the POSIX orchestration core.

These wrappers currently delegate to the existing internal cores under `bin/` while environment-specific implementations are migrated incrementally into system-native adapter trees.

Do not build or publish one universal executable and claim it can run across Windows, Debian, Fedora, macOS, BSD and extended Unix. Release artifacts are produced for a specific installer family and, where relevant, architecture/package format.

Shared environment intent belongs under `environments/`. System-specific implementation belongs under `installers/<family>/environments/` as it is added.

See `docs/installer-architecture.md` and `manifests/installer-families.json`.

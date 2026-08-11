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

Each entrypoint fails closed on the wrong host family. WSL2 is deliberately distinct from native Linux even where a reviewed WSL adapter delegates to the Linux payload.

The wrappers still use generic orchestration cores under `bin/` for unversioned catalog environments while version-specific implementations are migrated into system-native adapter trees.

## Current versioned-selector routing

Audit date: **2026-08-11**

| Selector | Linux | WSL2 | macOS | Windows |
| --- | --- | --- | --- | --- |
| `python@3.12` | routed / experimental | routed / experimental | routed / experimental | routed / experimental |
| `go@stable` | routed / experimental | routed / experimental | routed / experimental | routed / experimental |
| `rust@stable` | routed / experimental | routed / experimental | routed / experimental | staged adapter, top-level route gated |
| `flutter@stable` | routed / experimental | unsupported | routed / experimental | routed / experimental (amd64) |
| `kubectl@stable` | not centrally routed | not centrally routed | direct native adapter exists | direct native adapter exists |

This table describes release-entrypoint routing, **not promoted support**. Full support promotion still requires the governance gate set and authoritative target evidence.

The Go Windows workflow still contains an obsolete fail-closed expectation even though the Windows route is active; see issue #35. Windows Rust demonstrates the opposite staged condition: a reviewed native adapter exists, but the central Windows selector still intentionally blocks `rust@stable`.

## Placement rule

Shared versioned environment intent belongs under:

```text
environments/
```

System-specific implementation belongs under:

```text
installers/<family>/environments/
```

Portable security/integrity helpers may live under `lib/`, provided the release-facing entrypoint still proves the host/domain and the helper does not broaden support.

## Release rule

Do not build or publish one universal executable and claim it can run across Windows, Linux distributions, macOS, BSD, Solaris/illumos, and AIX. Release artifacts are produced for a specific installer family and, where relevant, architecture/package/archive format.

Adapter existence, direct component invocation, and shared selector routing are distinct states. None of them alone constitutes support promotion.

See `docs/installer-architecture.md`, `docs/REPOSITORY-STATUS.md`, and `manifests/installer-families.json`.

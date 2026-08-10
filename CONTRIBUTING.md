# Contributing to devkit-wulf

Thank you for contributing to `devkit-wulf`.

## Before you start

Read the repository contracts and current project status before making changes:

- [`AGENTS.md`](AGENTS.md) — mandatory governance and safety gates
- [`README.md`](README.md) — project overview and current behavior
- [`SECURITY.md`](SECURITY.md) — security policy
- [`ROADMAP.md`](ROADMAP.md) — phased implementation and promotion status
- [`research/upstream-sources.md`](research/upstream-sources.md) — dated primary-source research baseline

Repository changes must preserve unrelated user work and must not bypass the gates defined in `AGENTS.md`.

## Core contribution rules

`devkit-wulf` is a secure, manifest-driven environment orchestrator. Contributions must preserve:

- explicit support states;
- separation of host detection, platform adapters and environment definitions;
- non-mutating planning;
- fail-closed behavior for unknown or unverified combinations;
- verification after installation;
- minimal privilege escalation;
- Windows/WSL domain separation;
- host support vs cross-compilation target separation;
- idempotency and rollback awareness;
- current upstream research for version-sensitive behavior.

## Do not

Do not submit changes that:

- silently install unsupported targets;
- promote `experimental` support without the required validation gates;
- execute remote scripts without GATE-04/05/06 checks;
- weaken TLS, checksum or signature verification;
- use arbitrary third-party mirrors when an official source exists;
- conflate WSL2 with native Windows or native Linux state;
- replace system-managed Python or Ruby destructively;
- trigger unrelated full operating-system upgrades;
- remove shared or pre-existing dependencies without proven ownership;
- treat a compiler target as proof of native host support.

## Recommended workflow

1. Create a focused branch.
2. Research current official upstream documentation for every version-sensitive installer change.
3. Update manifests and implementation together.
4. Add or update verification and idempotency tests.
5. Update documentation and translations where applicable.
6. Run the relevant local checks.
7. Open a pull request that explains the affected platforms, environments and security implications.

## Local validation

Run the checks applicable to your host.

### POSIX hosts

```sh
python3 tests/validate_manifests.py
sh -n bin/devkit-wulf bootstrap/*.sh scripts/*.sh tests/*.sh
sh scripts/security-scan.sh
sh tests/test_cli.sh
```

If `shellcheck` is available:

```sh
shellcheck bin/devkit-wulf bootstrap/*.sh scripts/*.sh tests/*.sh
```

### Windows

```powershell
.\tests\test_powershell.ps1
```

If PSScriptAnalyzer is available:

```powershell
Invoke-ScriptAnalyzer -Path bin,bootstrap,tests -Recurse -Severity Error,Warning
```

Do not promote support solely because local installation succeeded once. Required CI or authoritative target-system validation must also pass.

## Pull request expectations

A pull request should state:

- what changed;
- why the change is needed;
- affected environments;
- affected hosts and architectures;
- installation strategy and source provenance;
- integrity/signature behavior;
- privilege requirements;
- verification performed;
- idempotency impact;
- uninstall/rollback ownership behavior;
- documentation and translation updates.

## Manifest changes

Environment and platform support decisions belong in versioned machine-readable manifests rather than scattered shell conditionals.

When changing a manifest:

- preserve explicit support states;
- use `unsupported` when no entry can be justified;
- keep host support separate from cross targets;
- record current upstream references and research dates;
- add a verification command;
- do not encode verification bypasses in installer arguments.

## Documentation and translations

`README.md` is the canonical English README. The repository currently maintains:

- [`README.de.md`](README.de.md)
- [`README.fr.md`](README.fr.md)
- [`README.pl.md`](README.pl.md)
- [`README.cn.md`](README.cn.md)
- [`README.ru.md`](README.ru.md)
- [`README.es.md`](README.es.md)

Commands, flags, environment IDs, support states and file paths should remain technically identical across translations.

See [`docs/TRANSLATIONS.md`](docs/TRANSLATIONS.md) for the translation policy.

## Security issues

Do not disclose suspected vulnerabilities in an unrelated public issue. Follow [`SECURITY.md`](SECURITY.md).

## Licensing

By contributing, you agree that your contribution may be distributed under the repository's [`MIT License`](LICENSE).
# Combined PHP Windows environment

Research/update date: **2026-08-11**

## Purpose

This orchestration layer combines the two independently verified Windows PHP components:

1. official PHP x64 NTS runtime;
2. official stable Composer PHAR.

The environment remains `experimental`.

## Central CLI

The native PowerShell CLI now resolves the Windows amd64 PHP environment to the effective strategy:

```text
php-windows
```

The declarative environment catalog remains `experimental` and retains `official-archive` as the researched component strategy; central routing selects the combined managed transaction only for native Windows amd64.

Typical flow:

```powershell
.\bin\devkit-wulf.ps1 plan php
.\bin\devkit-wulf.ps1 install php -Experimental
.\bin\devkit-wulf.ps1 verify php
```

`install php` without `-Experimental` is rejected before managed verification, release-index access, or installation work.

The central `verify php` path verifies the files in the devkit-managed PHP directory. An unrelated global `php.exe` or Composer installation cannot satisfy this gate.

## Install order

The combined transaction is intentionally ordered:

```text
PHP runtime
→ Composer
→ full environment verification
```

Composer is never attempted before the managed PHP runtime is ready, because Composer's helper requires the devkit PHP ownership marker and current `php.exe` hash.

## Plan

The combined plan is non-mutating and reports:

- Windows / amd64 target;
- `support: experimental`;
- effective `php-windows` strategy;
- managed destination;
- resolved PHP version/build;
- official PHP archive URL and SHA-256;
- official Composer PHAR/checksum URLs;
- component order;
- verification commands;
- `path_mutation: false`;
- `privilege: none`;
- the fact that automatic destructive rollback is not promised.

Resolving the current PHP release requires reading the pinned official release metadata, but the plan performs no persistent host mutation.

## Installation prerequisites

The component helpers retain their security prerequisites:

- Windows host architecture is amd64;
- `%LOCALAPPDATA%\devkit-wulf\php` is declared in the current process PATH;
- no relevant parent/destination is a reparse point;
- the state directory is safely writable.

With the default central CLI state location, the orchestration intent creates `%LOCALAPPDATA%\devkit-wulf` before the runtime component begins, so the managed installation parent exists without a separate manual bootstrap step. When `DEVKIT_WULF_STATE_DIR` is redirected elsewhere, the PHP installation parent is still independently required and is not invented from that custom state path.

The orchestrator does not persistently edit PATH and does not request Administrator elevation.

## Partial failure behavior

The orchestrator does not pretend that all two-component failures are safely reversible.

If the PHP runtime fails:

```text
runtime-component-failed
```

is recorded and Composer is not attempted.

If the runtime becomes ready but Composer fails:

```text
environment-incomplete
```

is recorded. The verified PHP runtime is not blindly deleted because safe component rollback/removal ownership is not yet established.

If both components install but the final environment verification fails:

```text
environment-verification-failed
```

is recorded separately.

Only after both component installs and the final verification succeed is:

```text
environment-verified
```

recorded.

The central CLI then records its own `installed-and-verified` observation only after managed verification succeeds.

## Final verification

The final verification requires both managed commands to execute:

```text
php --version
composer --version --no-ansi
```

The implementation resolves the exact managed files in the devkit PHP directory rather than accepting an unrelated executable elsewhere in PATH.

## State

The combined layer adds:

```text
php-windows-environment.jsonl
```

to the active devkit-wulf state directory.

The PHP runtime and Composer helpers continue to write their detailed component state records as well. During central installation the CLI passes its active state directory to the component/orchestration layer so all records remain under the selected state root.

The central state writer also refuses reparse-point state directories/files and non-file state paths.

## Idempotency

Idempotency is inherited from both components:

- PHP runtime requires exact devkit marker/version/source/archive hash/current `php.exe` hash;
- Composer requires exact PHAR source/hash plus binding to the current managed PHP hash.

The combined orchestrator can therefore be executed again without intentionally reinstalling unchanged components.

A newly published PHP or Composer release may intentionally produce a conflict until an explicit upgrade/migration workflow is implemented. Stable-release rotation must not silently overwrite a managed environment.

## Support policy

Central CLI activation does **not** promote support status. PHP on Windows remains experimental and amd64-only. The route exists to make the already verified components reachable through the normal CLI while preserving their gates.

## Component documentation

- [`php-windows.md`](php-windows.md)
- [`composer-windows.md`](composer-windows.md)

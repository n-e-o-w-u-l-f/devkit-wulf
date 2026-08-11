# Combined PHP Windows environment

Research/update date: **2026-08-11**

## Purpose

This orchestration layer combines the two independently verified Windows PHP components:

1. official PHP x64 NTS runtime;
2. official stable Composer PHAR.

The environment remains `experimental`.

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
- managed destination;
- resolved PHP version/build;
- official PHP archive URL and SHA-256;
- official Composer PHAR/checksum URLs;
- component order;
- verification commands;
- `path_mutation: false`;
- `privilege: none`;
- the fact that automatic destructive rollback is not promised.

## Installation prerequisites

The component helpers retain their existing prerequisites:

- `%LOCALAPPDATA%\devkit-wulf` already exists;
- `%LOCALAPPDATA%\devkit-wulf\php` is already declared in the current process PATH;
- no relevant parent/destination is a reparse point;
- the state directory is safely writable;
- Windows host architecture is amd64.

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

## Final verification

The default final verification requires both managed commands to execute:

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

to the normal devkit-wulf state directory.

This state is orchestration-level metadata; the PHP runtime and Composer helpers continue to write their own detailed component state records as well.

## Idempotency

Idempotency is inherited from both components:

- PHP runtime requires exact devkit marker/version/source/archive hash/current `php.exe` hash;
- Composer requires exact PHAR source/hash plus binding to the current managed PHP hash.

The combined orchestrator can therefore be executed again without intentionally reinstalling unchanged components.

A newly published PHP or Composer release may intentionally produce a conflict until an explicit upgrade/migration workflow is implemented. Stable-release rotation must not silently overwrite a managed environment.

## Central CLI integration

This layer is the transaction primitive required before central Windows `devkit-wulf install php` routing can safely stop failing closed.

A central CLI integration should invoke this orchestration only when:

- host is native Windows amd64;
- the support manifest still resolves PHP as `experimental`/`official-archive`;
- the user explicitly opts into experimental installation;
- plan output is shown first;
- the existing global PHP verification contract remains authoritative.

The orchestration layer itself does not promote support status.

## Component documentation

- [`php-windows.md`](php-windows.md)
- [`composer-windows.md`](composer-windows.md)

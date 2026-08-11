# Composer Windows PHAR component

Research date: **2026-08-11**

Status: **experimental**

## Purpose and current integration

This component supplies the Composer half of the Windows `php` environment without executing Composer's remote installer script.

The PHP runtime helper supplies a devkit-managed `php.exe`. This component supplies a verified `composer.phar` plus a deterministic `composer.bat` wrapper bound to that managed runtime. The combined orchestration is active through the Windows PHP environment layer and verifies:

```text
php --version
composer --version
```

The component remains independently integrity-gated and does not promote PHP support beyond `experimental`.

## Official sources

Only these stable Composer endpoints are used:

```text
https://getcomposer.org/download/latest-stable/composer.phar
https://getcomposer.org/download/latest-stable/composer.phar.sha256sum
```

Both must remain HTTPS on `getcomposer.org`. No Composer installer script is executed.

## Stable-release race gate

Because `latest-stable` can rotate while a transaction is in progress, the helper:

1. downloads and validates the published SHA-256 value;
2. downloads `composer.phar`;
3. downloads the SHA-256 metadata again;
4. requires both published hashes to be identical;
5. calculates the local PHAR SHA-256;
6. requires it to equal that stable hash.

If the stable pointer changes during the transaction, installation fails closed instead of combining metadata from different releases.

## Managed PHP prerequisite

Composer is not attached to an arbitrary PHP executable. The helper requires the devkit-managed runtime under:

```text
%LOCALAPPDATA%\devkit-wulf\php
```

and verifies both:

```text
php.exe
.devkit-wulf-artifact.json
```

The PHP marker must identify the devkit-managed Windows runtime and its recorded `php_sha256` must match the current executable. Changed, unowned, or unmarked PHP fails GATE-08 before Composer mutation.

## Installation layout

Composer is installed into the same managed PHP directory:

```text
%LOCALAPPDATA%\devkit-wulf\php\composer.phar
%LOCALAPPDATA%\devkit-wulf\php\composer.bat
%LOCALAPPDATA%\devkit-wulf\php\.devkit-wulf-composer.json
```

The wrapper is deterministic:

```bat
@echo off
"%~dp0php.exe" "%~dp0composer.phar" %*
```

This binds `composer` to the adjacent managed PHP runtime rather than an unrelated PHP elsewhere on PATH.

## PATH and privilege policy

The managed PHP directory must already be present in the current-process PATH contract. The helper does not modify persistent user/machine PATH, edit shell startup files, or request Administrator privileges.

## Functional verification

Before final placement, the staged PHAR is executed through the managed PHP runtime using the equivalent of:

```text
php.exe composer.phar --version --no-ansi
```

The output must contain a version matching the manifest policy. The functional check is repeated after installation; download/hash success alone is not sufficient.

## Marker, conflict handling, and idempotency

The Composer ownership marker binds the component to the Composer version, exact PHAR/checksum sources, PHAR SHA-256, and managed PHP SHA-256.

A subsequent installation is idempotent only when the PHAR, wrapper, marker, current stable hash, and PHP binding all verify. Unowned or changed files are refused instead of overwritten. A newly published stable Composer release is not silently substituted over an older managed release.

`safe_remove` remains false until ownership-aware removal is implemented.

## State tracking

State is appended to:

```text
%DEVKIT_WULF_STATE_DIR%\composer-windows.jsonl
```

or the default local devkit-wulf state directory. Reparse-point state paths are refused. Records include publisher, component/action, version, source URLs, PHAR/PHP hashes, destination, creation state, and `path_mutation: false`.

## Combined Windows PHP orchestration

The central integration now exists in:

```text
lib/php-windows-environment.ps1
```

The orchestration intentionally performs:

1. PHP runtime installation/observation;
2. Composer installation only after PHP ownership verification;
3. final `php --version` and `composer --version` environment verification.

Component failure and final verification failure are recorded distinctly. Central routing does not erase the individual integrity contracts and does not constitute support promotion.

## Upstream references

- Composer download: https://getcomposer.org/download/
- Composer introduction/install docs: https://getcomposer.org/doc/00-intro.md
- Latest stable PHAR: https://getcomposer.org/download/latest-stable/composer.phar
- Latest stable SHA-256: https://getcomposer.org/download/latest-stable/composer.phar.sha256sum

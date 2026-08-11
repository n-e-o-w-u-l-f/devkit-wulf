# Composer Windows PHAR component

Research date: **2026-08-11**

## Purpose

This component closes the Composer half of the existing Windows PHP environment contract without executing Composer's remote installer script.

The existing `php` environment verifies:

```text
php --version
composer --version
```

The PHP Windows runtime helper supplies the first executable. This Composer helper supplies a verified `composer.phar` plus a local `composer.bat` wrapper bound to the already devkit-managed `php.exe`.

Both remain experimental until central orchestration, hosted CI and target validation gates pass.

## Official sources

The helper uses only:

```text
https://getcomposer.org/download/latest-stable/composer.phar
https://getcomposer.org/download/latest-stable/composer.phar.sha256sum
```

Both URLs must remain HTTPS on `getcomposer.org`.

No Composer installer script is executed.

## Stable-release race gate

`latest-stable` can legitimately change when Composer publishes a new release. To avoid combining a checksum from one stable release with a PHAR from another, the helper uses this sequence:

1. download the official SHA-256 metadata;
2. parse and validate the first SHA-256 value;
3. download `composer.phar`;
4. download the official SHA-256 metadata again;
5. require both published hashes to be identical;
6. calculate the local PHAR SHA-256;
7. require it to equal the stable published hash.

If the stable pointer rotates during the transaction, installation fails and may be retried later.

No checksum bypass exists.

## Managed PHP prerequisite

Composer is not allowed to attach itself to an arbitrary PHP executable.

The helper requires the PHP runtime previously created by the devkit PHP Windows runtime component under:

```text
%LOCALAPPDATA%\devkit-wulf\php
```

It requires:

```text
php.exe
.devkit-wulf-artifact.json
```

and verifies that the marker says:

- environment `php`;
- component `php-windows-runtime`;
- the recorded `php_sha256` equals the current `php.exe` SHA-256.

A changed, unowned or unmarked PHP runtime causes GATE-08 to fail before Composer mutation.

## Installation layout

Composer is installed into the same user-local managed PHP directory:

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

This ensures `composer` uses the adjacent devkit-managed PHP runtime instead of whichever PHP executable happens to appear elsewhere in PATH.

## PATH policy

The managed PHP directory must already be present in the current process PATH.

The helper does not:

- modify persistent user PATH;
- modify machine PATH;
- edit shell startup files;
- require Administrator privileges.

`path_mutation` remains `false` in state records.

## Functional verification

Before committing the PHAR into the managed directory, the helper runs the staged PHAR through the managed PHP runtime using the equivalent of:

```text
php.exe composer.phar --version --no-ansi
```

The output must contain a semantic `MAJOR.MINOR.PATCH` Composer version matching the manifest policy.

After installation the same functional version check is repeated against the installed PHAR. A successful download/hash alone is not considered sufficient.

## Marker and idempotency

The Composer ownership marker records:

- environment `php`;
- component `composer`;
- publisher;
- Composer version;
- exact PHAR URL;
- exact checksum URL;
- PHAR SHA-256;
- managed PHP SHA-256.

A subsequent installation is idempotent only when:

1. `composer.phar`, `composer.bat` and the marker are regular non-reparse-point files;
2. the current PHAR hash matches the newly verified stable hash;
3. the marker source/hash match the current stable artifact;
4. the PHP hash still matches the runtime bound into the marker.

Any unowned or changed Composer file fails under GATE-08 instead of being overwritten or adopted.

A newly published stable Composer release is therefore not silently substituted over an older managed release without the normal conflict/migration decision.

## State tracking

State is appended to:

```text
%DEVKIT_WULF_STATE_DIR%\composer-windows.jsonl
```

or the default devkit-wulf local state directory when the override is absent.

State records include:

- publisher;
- environment/component;
- action;
- Composer version;
- source/checksum URLs;
- PHAR SHA-256;
- PHP SHA-256;
- destination;
- whether the artifact was created;
- `path_mutation: false`.

Reparse-point state files/directories are refused.

## Integration status

With the runtime and Composer helpers both present, the two executable requirements of the Windows PHP environment can now be satisfied through separately verified components.

Central `devkit-wulf install php` routing should still be activated only in a follow-up that:

1. plans both components together;
2. installs PHP runtime first;
3. installs Composer only after PHP ownership verification;
4. runs the existing `php --version` and `composer --version` environment verification;
5. preserves the current experimental support state;
6. adds end-to-end Windows target validation.

## Upstream references

- Composer download: https://getcomposer.org/download/
- Composer introduction/install docs: https://getcomposer.org/doc/00-intro.md
- Latest stable PHAR: https://getcomposer.org/download/latest-stable/composer.phar
- Latest stable SHA-256: https://getcomposer.org/download/latest-stable/composer.phar.sha256sum

# PHP Windows runtime archive

Research date: **2026-08-11**

Status: **experimental**

## Integration boundary

The Windows `php` environment is now orchestrated as a coordinated PHP-runtime + Composer environment. The runtime helper documented here remains a distinct integrity component, but it is no longer a standalone future-only path.

Central Windows orchestration plans and installs the PHP runtime first, validates devkit ownership, installs Composer through its separately verified component, and then performs the environment-level verification:

```text
php --version
composer --version
```

A PHP runtime archive by itself must still never be reported as a complete PHP environment.

## Official release metadata

The runtime helper uses the official Windows PHP release index:

```text
https://windows.php.net/downloads/releases/releases.json
```

and constructs archive URLs only below:

```text
https://windows.php.net/downloads/releases
```

It selects the highest maintained numeric branch, validates the release version, selects the highest matching x64 non-thread-safe build (`nts-vsN-x64`), requires a safe ZIP filename plus a 64-hex SHA-256 value, and keeps the final archive URL on `windows.php.net`.

## Architecture and runtime choice

The reviewed runtime path is CLI-oriented and therefore uses the Windows x64 NTS build:

```text
thread_safety: nts
architecture: amd64
```

ARM64 is not advertised by this helper.

## User-local destination

The runtime is staged and installed under:

```text
%LOCALAPPDATA%\devkit-wulf\php
```

Before installation:

- `%LOCALAPPDATA%\devkit-wulf` must exist and must not be a reparse point;
- the managed PHP directory must already be represented in the current-process PATH contract;
- persistent user or machine PATH is not edited;
- Administrator elevation is not used.

## Integrity and archive safety

The archive SHA-256 is obtained from the same official release record that supplies the ZIP filename. The helper downloads release metadata and the archive over HTTPS, calculates SHA-256 with `Get-FileHash`, fails on mismatch, validates ZIP paths before extraction, stages extraction under an approved user-local parent, and records the installed `php.exe` hash.

ZIP entries are rejected when they are absolute, drive/URI-qualified, contain `.`/`..` traversal, use unsafe separators, or resolve outside the staging root. `php.exe` must be a normal non-reparse-point file.

No TLS or checksum bypass is implemented.

## Conflict, ownership, and idempotency

Successful installation creates:

```text
%LOCALAPPDATA%\devkit-wulf\php\.devkit-wulf-artifact.json
```

The marker binds the managed directory to the component, PHP version/build, exact release sources, archive SHA-256, and installed `php.exe` SHA-256.

An arbitrary existing PHP directory is not adopted. A second installation is idempotent only when the marker and executable hash prove that the currently resolved artifact is exactly the managed artifact. A changed, newer, foreign, or unowned destination fails closed instead of being overwritten.

`safe_remove` remains false until the ownership-aware removal gate is implemented.

## State tracking

The runtime component appends records to:

```text
%DEVKIT_WULF_STATE_DIR%\php-windows.jsonl
```

or the default devkit-wulf local state directory. State-directory and state-file reparse points are rejected.

Records capture mutation intent, installed/observed artifact state, publisher, version/build, source metadata, hashes, destination, and `path_mutation: false`.

## Composer integration

Composer is a separate verified component documented in `docs/environments/composer-windows.md`. The combined Windows PHP orchestrator is implemented in:

```text
lib/php-windows-environment.ps1
```

Its install order is intentionally:

1. PHP runtime;
2. Composer after PHP ownership verification;
3. environment-level verification of both commands.

A Composer component failure or final environment-verification failure is recorded as an incomplete/failed environment; it is not reported as success merely because PHP was installed.

## Windows PowerShell compatibility

The implementation targets Windows PowerShell 5.1 and PowerShell 7. Windows PowerShell 5.1 downloads use process-local TLS 1.2 selection and `Invoke-WebRequest -UseBasicParsing`. No persistent execution-policy or TLS setting is changed.

## Upstream references

- PHP Windows downloads: https://windows.php.net/download/
- Windows release metadata: https://windows.php.net/downloads/releases/releases.json
- PHP Windows installation manual: https://www.php.net/manual/en/install.windows.php

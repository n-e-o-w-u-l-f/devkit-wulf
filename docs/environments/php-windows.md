# PHP Windows runtime archive

Research date: **2026-08-11**

## Integration boundary

The existing `php` environment remains `experimental`.

This helper implements only the **official Windows PHP runtime archive** component. It is intentionally not wired into the central `devkit-wulf install php` success path yet, because the environment contract also verifies Composer.

A PHP runtime archive install must not be reported as a complete PHP environment while `composer --version` is still unresolved.

## Official release metadata

The helper uses the official Windows PHP release index:

```text
https://windows.php.net/downloads/releases/releases.json
```

and constructs archive URLs only below:

```text
https://windows.php.net/downloads/releases
```

The release index contains maintained numeric branches, build entries, ZIP paths and SHA-256 metadata.

The helper:

1. enumerates numeric `MAJOR.MINOR` branches;
2. selects the highest branch;
3. validates the release `version` against that branch;
4. selects the highest matching x64 non-thread-safe build key (`nts-vsN-x64`);
5. requires ZIP metadata with a safe filename and a 64-hex SHA-256;
6. constructs the final archive URL on `windows.php.net` only.

## Why NTS

The devkit runtime path is CLI-oriented. The manifest therefore selects the non-thread-safe x64 Windows build rather than silently choosing a thread-safe Apache-module-oriented runtime.

This choice is explicit in the machine-readable contract:

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

- `%LOCALAPPDATA%\devkit-wulf` must already exist;
- the parent must not be a reparse point;
- `%LOCALAPPDATA%\devkit-wulf\php` must already be present in the current process `PATH`;
- the helper does not edit persistent user or machine PATH;
- no Administrator elevation is used.

The no-implicit-PATH rule is intentional. A caller can prepare the current process before installation, for example:

```powershell
New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\devkit-wulf" | Out-Null
$env:PATH = "$env:LOCALAPPDATA\devkit-wulf\php;$env:PATH"
```

## Integrity

The archive SHA-256 comes from the same official `releases.json` record that supplies the ZIP filename.

The helper:

1. downloads the release index over HTTPS;
2. resolves the x64 NTS ZIP and SHA-256;
3. downloads the ZIP from `windows.php.net`;
4. computes SHA-256 with `Get-FileHash`;
5. hard-fails on mismatch;
6. validates ZIP paths before extraction;
7. extracts into a user-local staging directory;
8. calculates the extracted `php.exe` SHA-256 for ownership tracking.

No TLS or checksum bypass is implemented.

## ZIP safety

Before extraction, every ZIP entry is checked.

Entries are rejected when they contain:

- absolute paths;
- backslash path separators in archive entry names;
- drive/URI colon syntax;
- `.` or `..` traversal components;
- a resolved destination outside the staging root.

`php.exe` must be a normal non-reparse-point file after extraction.

## Conflict and idempotency policy

The helper does not adopt an arbitrary existing PHP directory.

On successful first install it writes:

```text
%LOCALAPPDATA%\devkit-wulf\php\.devkit-wulf-artifact.json
```

The marker records:

- component ID;
- PHP version;
- selected build key;
- exact archive URL;
- release-index URL;
- archive SHA-256;
- installed `php.exe` SHA-256.

A second installation is idempotent only when the marker and the current `php.exe` prove that the directory is exactly the currently resolved devkit-managed artifact.

Any different or unowned existing directory fails under GATE-08. A newly published PHP release is therefore not silently installed over an older managed runtime; upgrade/migration semantics must be explicit first.

## State tracking

The helper uses:

```text
%DEVKIT_WULF_STATE_DIR%\php-windows.jsonl
```

when `DEVKIT_WULF_STATE_DIR` is set, otherwise:

```text
%LOCALAPPDATA%\devkit-wulf\state\php-windows.jsonl
```

State-directory and state-file reparse points are rejected.

Records include mutation intent, installed artifact observations, publisher, branch, version, build, archive source, release index, archive SHA-256, `php.exe` SHA-256, destination and `path_mutation: false`.

## Composer remains a separate gate

The repository's existing PHP environment verifies both:

```text
php --version
composer --version
```

This runtime helper satisfies only the first component. Composer must be installed through a separately researched and integrity-verified path before the central PHP environment installer can declare success.

The helper therefore remains standalone and does not weaken GATE-12.

## Windows PowerShell compatibility

The implementation targets Windows PowerShell 5.1 and PowerShell 7.

For Windows PowerShell 5.1, HTTPS downloads use process-local TLS 1.2 selection and `Invoke-WebRequest -UseBasicParsing`. No persistent execution-policy or TLS setting is changed.

## Upstream references

- PHP Windows downloads: https://windows.php.net/download/
- Windows release metadata: https://windows.php.net/downloads/releases/releases.json
- PHP Windows installation manual: https://www.php.net/manual/en/install.windows.php

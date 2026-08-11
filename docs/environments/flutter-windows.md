# Flutter Windows verified artifact contract

Research/update date: **2026-08-11**

Status: **experimental**

## Scope and routing

This contract realizes the Windows `flutter@stable` selector as a native PowerShell-managed verified artifact for **Windows amd64 only**.

The central release-facing Windows entrypoint now routes `flutter@stable` to:

```text
installers/windows/environments/flutter-stable.ps1
```

which uses the reviewed Windows artifact contract/helper. This is an active experimental route, not a support promotion.

The generic unversioned `flutter` environment remains a separate catalog concern. Windows ARM64 and WSL are not added by this contract.

## Official release metadata

The adapter reads only the pinned official Flutter Windows release index:

```text
https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json
```

The index must report the exact pinned base URL:

```text
https://storage.googleapis.com/flutter_infra_release/releases
```

Release selection requires:

1. `current_release.stable`;
2. a release whose `hash` equals that stable hash;
3. `channel == stable`;
4. `dart_sdk_arch == x64`;
5. a safe semantic Flutter version;
6. an archive path matching the official stable Windows ZIP shape;
7. a 64-hex SHA-256 value from the same release entry.

The final archive URL must remain on `storage.googleapis.com` under `/flutter_infra_release/releases/`.

## Destination and PATH policy

Managed destination:

```text
%USERPROFILE%\develop\flutter
```

Expected managed PATH directory:

```text
%USERPROFILE%\develop\flutter\bin
```

Ownership marker:

```text
%USERPROFILE%\develop\flutter\.devkit-wulf-artifact.json
```

The approved install parent must already exist and must not be a reparse point. The managed Flutter `bin` directory must already be represented in the current-process PATH contract.

The helper performs **no persistent PATH mutation** and requests **no Administrator elevation**.

## ZIP safety and staging

Every ZIP entry is inspected before extraction. The helper rejects absolute/drive-qualified paths, backslashes, traversal, entries outside the exact `flutter/` root, Unix symlinks, and Windows reparse-point entries.

The archive must contain both critical managed launchers:

```text
flutter/bin/flutter.bat
flutter/bin/dart.bat
```

Staging is created inside the approved user-local parent. Recursive cleanup is permitted only after proving the staging path belongs to that parent, matches the expected randomized staging-name contract, and is not a reparse point.

The verified `flutter` tree moves into its final location only after integrity and ownership metadata are prepared.

## Ownership and idempotency

The marker records environment/publisher/platform/architecture, resolved Flutter version, official archive source, archive SHA-256, and hashes for `flutter.bat` and `dart.bat`.

A foreign existing Flutter directory is refused before release-index network access. A repeated installation is idempotent only when the existing marker and critical files verify and the resolved stable artifact still matches that managed installation.

A newer stable release does not silently overwrite an older managed SDK. Explicit future upgrade/migration semantics are required.

`safe_remove` remains false until ownership-aware removal is implemented.

## Managed verification

Artifact-level verification checks the exact managed destination, reparse-point policy, marker identity, source/version/hash syntax, and current critical-file hashes.

It intentionally avoids invoking Flutter as part of artifact integrity verification because Flutter command execution may initialize cache state. Environment smoke verification remains a distinct layer.

## State

Detailed records are appended to:

```text
<devkit-wulf-state>\flutter-windows.jsonl
```

State directory/file reparse points and non-file state paths are refused. Recorded actions include mutation intent, verified installation, and exact managed observation.

## Offline fixture coverage

The Windows fixture covers:

- amd64 acceptance and ARM64 refusal;
- stable/x64 release selection;
- pinned official source/base URL;
- SHA-256 verification;
- non-mutating plan behavior;
- foreign destination and PATH refusal before network use;
- exact ownership marker and critical hashes;
- managed verification;
- offline/idempotent second installation;
- critical-file tamper detection;
- checksum mismatch refusal;
- traversal/wrong-root ZIP refusal;
- state/install-parent reparse-point refusal.

## Support policy

`flutter@stable` on native Windows amd64 remains **experimental** and requires explicit `-Experimental` opt-in for installation. Adapter presence, offline fixtures, or successful local verification do not promote support without the complete governance gate set.

## Upstream references

- Flutter SDK archive: https://docs.flutter.dev/install/archive
- Flutter manual installation: https://docs.flutter.dev/install/manual
- Flutter Windows release index: https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json

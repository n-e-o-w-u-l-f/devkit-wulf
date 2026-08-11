# Flutter Windows verified artifact contract

Research/update date: **2026-08-11**

Status: **experimental**

## Scope

This contract realizes the existing Windows `official-archive` Flutter environment as a native PowerShell-managed artifact for **Windows amd64 only**.

It does not add Windows ARM64 support and does not promote the Flutter environment beyond `experimental`.

Central `devkit-wulf.ps1` routing remains a separate integration step after this helper contract is merged.

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

The parent `%USERPROFILE%\develop` must already exist, be a real directory and not be a reparse point. The managed Flutter `bin` directory must already be present in the current process PATH.

The helper performs **no persistent PATH mutation** and requests **no Administrator elevation**.

## ZIP safety

Before extraction, every ZIP entry is inspected.

The helper rejects entries that:

- are absolute;
- use drive-qualified syntax;
- contain backslashes;
- contain `..` path traversal;
- live outside the exact `flutter/` root;
- represent Unix symlinks;
- carry the Windows reparse-point attribute.

The archive must contain both critical managed launchers:

```text
flutter/bin/flutter.bat
flutter/bin/dart.bat
```

Only after SHA-256 and ZIP-path checks pass is the archive extracted.

## Staging and placement

Staging is created inside the approved `%USERPROFILE%\develop` parent so final placement stays on the same filesystem.

Staging cleanup is recursively allowed only after proving all of the following:

- the path is a child of the exact approved install parent;
- the leaf matches `.devkit-wulf-flutter-<32 hex>`;
- the staging directory is not a reparse point.

The verified `flutter` directory is moved into its final location only after critical-file hashes and the ownership marker have been prepared in staging.

## Ownership and idempotency

The marker records:

- environment `flutter`;
- publisher `Flutter Authors / Google`;
- platform `windows`;
- architecture `amd64`;
- resolved Flutter version;
- official archive source URL;
- archive SHA-256;
- SHA-256 values for `bin/flutter.bat` and `bin/dart.bat`.

A foreign existing Flutter directory with no valid devkit marker is refused **before release-index network access**.

A repeated installation is idempotent only when:

- the current managed marker verifies;
- critical launcher hashes still match;
- the currently resolved stable release matches the marker version/source/archive hash.

A newer stable release does not silently overwrite an existing managed SDK. Explicit future upgrade/migration semantics are required.

## Managed verification

`Test-DevkitFlutterWindowsManagedVerification` is offline with respect to release discovery.

It validates:

- exact managed destination;
- non-reparse destination and marker;
- marker publisher/environment/platform/architecture;
- recorded version/source/archive hash syntax;
- current SHA-256 values of `flutter.bat` and `dart.bat` against the marker.

It intentionally does not invoke Flutter during artifact-level verification because Flutter command execution may initialize cache state. CLI-level environment smoke verification remains a separate integration concern.

## State

Detailed records are appended to:

```text
<devkit-wulf-state>\flutter-windows.jsonl
```

State directory/file reparse points and non-file state paths are refused.

Actions include:

```text
mutation-intent
installed-verified-artifact
observed-exact-artifact
```

## Offline fixture coverage

The Windows fixture verifies:

- exact amd64 gate and ARM64 refusal;
- stable/x64 release selection;
- pinned base URL;
- official archive URL construction;
- SHA-256 verification;
- non-mutating plan;
- foreign destination refusal before network;
- PATH refusal before network;
- exact installation marker/hashes;
- managed verification;
- idempotent second installation without archive redownload;
- critical-file tamper detection;
- checksum mismatch refusal;
- traversal ZIP refusal;
- wrong-root ZIP refusal;
- state-directory reparse-point refusal;
- install-parent reparse-point refusal.

## Support policy

This is an implementation of the already declared Windows amd64 experimental archive path, not a support expansion.

Windows ARM64 remains unsupported by this contract. `safe_remove` remains false until removal ownership is implemented.

## Upstream references

- Flutter SDK archive: https://docs.flutter.dev/install/archive
- Flutter manual installation: https://docs.flutter.dev/install/manual
- Flutter Windows release index: https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json

# Flutter SDK environment

Research date: **2026-08-11**

## Support boundary

`flutter` remains `experimental`. The verified SDK archive adapter does not promote any host/platform combination to supported status.

The current POSIX adapter covers the Flutter SDK archive path for:

- Linux x64 (`amd64` host mapping);
- macOS Intel (`amd64` host mapping);
- macOS Apple Silicon (`arm64`).

Windows remains on the existing `official-archive` declaration but requires a separate native PowerShell archive adapter before it can be automated safely.

The current official Flutter SDK archive page exposes Linux as x64, macOS as Intel/Arm64, and Windows as x64. The POSIX artifact catalog therefore does not silently invent a Linux Arm64 SDK archive path.

## Official release metadata

Flutter's release publisher generates separate JSON indexes for Linux, macOS and Windows. The publisher source defines the release metadata base URL as:

```text
https://storage.googleapis.com/flutter_infra_release/releases
```

The POSIX adapter uses:

```text
https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json
https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json
```

The release index provides:

- `base_url`;
- `current_release` channel hashes;
- release `hash`;
- `channel`;
- `version`;
- `dart_sdk_arch`;
- archive path;
- SHA-256.

`devkit-wulf` selects the current `stable` hash and then requires an entry matching both that hash and the host's mapped `dart_sdk_arch`.

The returned `base_url` must exactly match the manifest-pinned Flutter release base URL before any archive URL is constructed.

## Integrity gate

The archive URL is derived only from:

1. the manifest-pinned official release-index URL;
2. the release index's exact `base_url` after equality validation;
3. the selected stable release's relative archive path.

The relative archive path is rejected if it is absolute, contains backslashes, empty path segments, `.` or `..` traversal components.

The SDK archive is downloaded before extraction. Its local SHA-256 must exactly match the `sha256` value in the official release metadata. A malformed hash, missing local SHA-256 implementation or mismatch is a hard failure.

No checksum-bypass mode exists.

## Default installation location

The POSIX adapter uses a deterministic user-owned location:

```text
$HOME/develop/flutter
```

and expects Flutter's executable directory to be:

```text
$HOME/develop/flutter/bin
```

Before installation, the operator must prepare the parent and current-shell PATH explicitly, for example:

```sh
mkdir -p "$HOME/develop"
export PATH="$HOME/develop/flutter/bin:$PATH"
```

`devkit-wulf` does not silently edit shell startup files or PATH for this archive path.

The PATH entry may exist before the SDK directory itself exists. This allows `plan` and the installation gate to preserve the no-implicit-PATH-mutation policy while still verifying `flutter` through the selected SDK after extraction.

## Archive safety

Linux uses the official `tar.xz` SDK archive. macOS uses the official ZIP SDK archive.

Before extraction, `devkit-wulf` lists the archive and rejects it unless every entry:

- is relative;
- is rooted under the expected `flutter/` directory;
- contains no `..` path traversal component;
- contains no backslash path separator.

Extraction occurs in a staging directory created inside the final parent directory. This keeps the final placement on the same filesystem and allows the verified `flutter/` tree to be moved into place only after extraction checks pass.

The extracted `flutter/bin/flutter` must exist and be executable before the SDK is installed.

## Conflict and idempotency policy

The adapter never overwrites an arbitrary existing `$HOME/develop/flutter` directory.

On first successful install it writes a small devkit-owned marker:

```text
$HOME/develop/flutter/.devkit-wulf-artifact.json
```

The marker records:

- environment ID;
- resolved Flutter version;
- exact archive source URL;
- verified SHA-256.

A second installation is treated as idempotent only when:

1. the destination is a real directory, not a symlink;
2. the marker is a real file, not a symlink;
3. environment/version/source/hash exactly match the newly resolved stable release;
4. `flutter/bin/flutter` is executable.

Any other existing SDK directory is a GATE-08 conflict and requires an explicit future upgrade/migration workflow.

This conservative rule also means a newly published stable Flutter release will not silently replace an existing managed SDK. Version upgrades require explicit migration semantics before they are automated.

## State tracking

Artifact operations continue to use `artifacts.jsonl` in the devkit-wulf state directory.

The state path rejects both file and state-directory symlinks. For archive installs, records include:

- publisher;
- resolved version;
- release metadata URL;
- exact archive source URL;
- archive SHA-256;
- destination;
- mutation intent;
- successful installation or exact-artifact observation;
- `path_mutation: false`.

## Verification

After the verified archive is placed, the normal environment verification gate remains authoritative:

```text
flutter --version
dart --version
flutter doctor
```

Because the adapter requires `$HOME/develop/flutter/bin` to already be present in the current PATH, these verification commands resolve against the newly installed SDK without modifying the user's shell configuration.

A successful archive extraction alone is not considered a successful Flutter environment installation.

## Current limitations

- Windows archive installation still requires a native PowerShell implementation.
- Linux Arm64 is not mapped by the current verified archive adapter because the current official SDK archive documentation used for this research advertises Linux x64.
- Existing Flutter installations are not adopted automatically.
- Automatic stable-version upgrades are intentionally refused until migration/state ownership semantics are implemented.
- Android, Xcode and other platform toolchains remain independent environments and are not silently installed by the Flutter SDK adapter.

## Upstream references

- Flutter SDK archive: https://docs.flutter.dev/install/archive
- Flutter manual installation: https://docs.flutter.dev/install/manual
- Flutter repository: https://github.com/flutter/flutter
- Flutter release publisher source: https://github.com/flutter/flutter/blob/main/dev/bots/prepare_package/archive_publisher.dart
- Flutter packaging constants: https://github.com/flutter/flutter/blob/main/dev/bots/prepare_package/common.dart

# Flutter stable system-native environment

Research date: **2026-08-11**

Selector:

```text
flutter@stable
```

## Responsibility split

Flutter is deliberately split by host family instead of pretending one installer format is universal.

Shared selector contract:

```text
environments/flutter/stable.json
```

Reviewed artifact contracts:

```text
Linux/macOS: manifests/artifacts.json + lib/artifacts.sh
Windows:     manifests/flutter-windows.json + lib/flutter-windows.ps1
```

Linux and macOS share only portable POSIX environment-level verification in `lib/flutter-posix-environment.sh`. Windows does not source or execute that POSIX installer; it uses its native PowerShell contract.

The unversioned `flutter` environment remains unchanged.

## Native Linux

```sh
./installers/linux/devkit-wulf.sh plan flutter@stable
./installers/linux/devkit-wulf.sh install flutter@stable --experimental
./installers/linux/devkit-wulf.sh verify flutter@stable
```

Adapter:

```text
installers/linux/environments/flutter-stable.sh
```

The reviewed Linux archive contract currently maps **amd64 only**. The adapter uses Flutter's official stable Linux release index, the SHA-256 carried by the release metadata, strict archive-root checks and the user-local destination:

```text
$HOME/develop/flutter
```

The adapter performs no privilege escalation and no PATH mutation. The managed Flutter bin directory must be handled explicitly by the operator as described by the existing artifact contract.

## macOS

```sh
./installers/macos/devkit-wulf.sh plan flutter@stable
./installers/macos/devkit-wulf.sh install flutter@stable --experimental
./installers/macos/devkit-wulf.sh verify flutter@stable
```

Adapter:

```text
installers/macos/environments/flutter-stable.sh
```

The reviewed macOS archive contract maps:

```text
amd64
arm64
```

It uses the official macOS stable release index and verified ZIP artifact. No Linux tar path or Windows ZIP helper is reused as the release-facing installer.

## Windows native

```powershell
.\installers\windows\devkit-wulf.ps1 plan 'flutter@stable'
.\installers\windows\devkit-wulf.ps1 install 'flutter@stable' -Experimental
.\installers\windows\devkit-wulf.ps1 verify 'flutter@stable'
```

Adapter:

```text
installers/windows/environments/flutter-stable.ps1
```

The adapter uses the already-reviewed native PowerShell contract:

```text
manifests/flutter-windows.json
lib/flutter-windows.ps1
```

The current Windows artifact contract is **amd64 only**. It consumes Flutter's official Windows release index, verifies the release SHA-256, performs ZIP safety checks, keeps installation user-local and records marker-bound hashes for `flutter.bat` and `dart.bat`.

Selector-level verification first requires the existing managed marker/hash verification, then runs the exact managed `flutter.bat --version` and `dart.bat --version` commands. A global unrelated Flutter installation does not satisfy this selector.

## WSL2

`flutter@stable` is currently **not enabled for WSL2**.

This is intentional. The reviewed native Linux archive contract is not automatically inherited into WSL merely because the WSL kernel presents a Linux userspace. Flutter SDK use in WSL has additional host/domain implications and requires its own validation contract before promotion.

The WSL release entrypoint therefore rejects this selector before generic-core fallback.

## BSD and extended Unix

BSD, Solaris/illumos and AIX are unsupported for this selector because the reviewed artifact contracts do not contain corresponding Flutter host archives.

## POSIX ownership hardening

The selector adds an environment-level managed marker layer on top of the existing POSIX artifact transaction.

For a newly installed selector-owned SDK, the marker is extended with SHA-256 values for:

```text
bin/flutter
bin/dart
```

Verification requires:

- real SDK and `bin/` directories, not symlinks;
- a real ownership marker;
- official Flutter storage URL;
- the correct platform release path (`stable/linux/` or `stable/macos/`);
- matching critical launcher hashes;
- successful exact managed `flutter --version` and `dart --version` execution.

An existing Flutter SDK that predates these selector-level critical hashes is not silently adopted. `install flutter@stable` fails with an explicit migration/reinstall requirement instead of writing new ownership hashes over an unverifiable existing tree.

## Security boundary

- stable release metadata from reviewed Flutter endpoints;
- archive SHA-256 before extraction;
- host-specific archive handling;
- no privilege escalation;
- no implicit PATH edits;
- critical-file tamper detection;
- no automatic SDK replacement/upgrade;
- explicit experimental opt-in for installation;
- Windows and POSIX implementations remain separate executable contracts.

See also `docs/environments/flutter.md`, `docs/environments/flutter-windows.md`, and `docs/installer-architecture.md`.

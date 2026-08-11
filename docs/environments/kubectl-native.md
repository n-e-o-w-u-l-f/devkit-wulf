# Native kubectl stable artifact contracts

Research date: **2026-08-11**

These contracts prepare system-native Windows and macOS implementations for the future `kubectl@stable` selector. They intentionally do not reuse a Linux binary installer as a universal executable.

## Shared data, separate executables

Shared artifact data:

```text
manifests/kubectl-native.json
```

Native implementations:

```text
Windows: lib/kubectl-windows.ps1
         installers/windows/environments/kubectl-stable.ps1

macOS:   lib/kubectl-macos.sh
         installers/macos/environments/kubectl-stable.sh
```

The stable version resolver is common data:

```text
https://dl.k8s.io/release/stable.txt
```

but filesystem roots, download primitives, executable handling and runtime verification remain system-specific.

## Windows native

The reviewed Windows contract currently enables **amd64 only**. This is deliberately narrower than guessing that every Kubernetes client build target is a reviewed devkit-wulf Windows host path.

Artifact URLs are derived only as:

```text
https://dl.k8s.io/release/<version>/bin/windows/amd64/kubectl.exe
https://dl.k8s.io/release/<version>/bin/windows/amd64/kubectl.exe.sha256
```

Destination:

```text
%LOCALAPPDATA%\devkit-wulf\kubectl\bin\kubectl.exe
```

The managed `bin` directory must already be present in the current process PATH. The helper does not edit persistent environment variables or registry PATH state.

The Windows transaction:

1. resolves and validates the stable `vX.Y.Z` string;
2. constructs only the pinned `dl.k8s.io/release/.../windows/amd64/` URLs;
3. downloads the `.sha256` sidecar;
4. downloads `kubectl.exe`;
5. requires an exact SHA-256 match before placement;
6. rejects destination/staging reparse points;
7. writes a selector ownership marker;
8. verifies the exact managed binary hash;
9. executes only the managed binary with:

```text
kubectl.exe version --client=true --output=json
```

and requires `.clientVersion.gitVersion` to match the marker version.

A valid existing selector-managed binary is accepted as an offline idempotent observation. A foreign or modified destination fails GATE-08 before stable-version network resolution.

No Administrator elevation, MSI, WinGet or persistent PATH mutation is part of this selector contract.

Direct experimental adapter:

```powershell
.\installers\windows\environments\kubectl-stable.ps1 plan
.\installers\windows\environments\kubectl-stable.ps1 install -Experimental
.\installers\windows\environments\kubectl-stable.ps1 verify
```

## macOS native

Reviewed host architectures:

```text
amd64
arm64
```

Artifact URLs are derived only as:

```text
https://dl.k8s.io/release/<version>/bin/darwin/<arch>/kubectl
https://dl.k8s.io/release/<version>/bin/darwin/<arch>/kubectl.sha256
```

Destination:

```text
$HOME/.local/share/devkit-wulf/kubectl/bin/kubectl
```

The helper keeps the binary user-local, requires the managed `bin` directory to already be in the current process PATH, downloads over HTTPS, verifies SHA-256 before placement, applies mode `0755`, writes a marker and executes the exact managed binary with client-only JSON version output.

No `sudo`, Homebrew installation, shell-profile edit or persistent PATH mutation is part of this artifact path.

Direct experimental adapter:

```sh
sh installers/macos/environments/kubectl-stable.sh plan
sh installers/macos/environments/kubectl-stable.sh install --experimental
sh installers/macos/environments/kubectl-stable.sh verify
```

The adapter will be marked executable when it is promoted into a release-facing selector route.

## Linux

The repository already has a separately reviewed Linux kubectl binary contract in `manifests/artifacts.json` / `lib/artifacts.sh`. This PR does not replace or rewrite that Linux transaction.

A later selector-routing PR can combine the reviewed Linux, Windows and macOS implementations under a shared `kubectl@stable` environment contract while preserving system-native executable boundaries.

## WSL2

No Windows binary is used inside WSL. When `kubectl@stable` is wired for WSL, the WSL domain must explicitly select a reviewed Linux payload and remain independent from Windows filesystem/PATH behavior.

## Offline regression tests

Windows:

```text
tests/test_kubectl_windows.ps1
```

The fixture compiles a local test executable, provides local `stable.txt` and checksum content, overrides only the download function inside the test session, and covers stable resolution, SHA-256, non-mutating plan, installation, managed runtime verification, offline second install, tamper detection and foreign-destination conflict before network.

macOS:

```text
tests/test_kubectl_macos.sh
```

The fixture uses a local executable shell stub plus local version/checksum files and covers the corresponding macOS transaction without live downloads.

CI intentionally performs no live kubectl artifact download.

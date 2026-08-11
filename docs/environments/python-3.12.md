# Python 3.12 system-native environment

Research date: **2026-08-11**

## Shared contract

The platform-neutral environment contract is:

```text
environments/python/3.12.json
```

It defines the common outcome:

- CPython 3.12;
- `venv` available;
- `pip` verified inside a project virtual environment;
- no replacement of an operating system's generic/system Python;
- no global package installation through `pip`;
- no devkit-owned rewriting of global Python aliases;
- the exact runtime used for verification must be owned by the selected adapter/package manager.

The installer commands themselves are **not** shared blindly across operating systems.

## Lifecycle boundary

Python 3.12 is in the security-only stage and is scheduled to receive source-only security releases until October 2028.

At this research date, the current upstream release is **3.12.13**. Python.org stopped publishing the classic per-release Windows/macOS binary installers after **3.12.10**. The Windows implementation therefore does not download `python-3.12.10.exe` and pretend it is the current Python 3.12 security level.

## Windows native

Entrypoint:

```powershell
.\installers\windows\environments\python-3.12.ps1 plan
.\installers\windows\environments\python-3.12.ps1 install -Experimental
.\installers\windows\environments\python-3.12.ps1 verify
```

Strategy: **Python Install Manager**.

The adapter requires `pymanager` to already be installed. Installation of the manager itself is kept separate from installation of the Python 3.12 runtime.

The adapter:

1. resolves tag `3.12` through the manager's online index;
2. uses the manager's `--dry-run` path during `plan`;
3. accepts only a runtime returned by `pymanager list --only-managed ...`;
4. requires the runtime to report Python 3.12;
5. requires an upstream-style runtime patch at least equal to the researched baseline 3.12.13;
6. creates an ephemeral virtual environment and checks `pip` inside it;
7. does not force/update an older managed runtime automatically because manager updates may replace runtime modifications.

The adapter never uses an arbitrary `python.exe` found on PATH as proof of success.

## Native Linux: Ubuntu 24.04 only

Entrypoint:

```sh
./installers/linux/environments/python-3.12.sh plan
./installers/linux/environments/python-3.12.sh install --experimental
./installers/linux/environments/python-3.12.sh verify
```

The initial native Linux implementation is intentionally restricted to exact Ubuntu **24.04** (`ID=ubuntu`, `VERSION_ID=24.04`).

Packages:

```text
python3.12
python3.12-venv
```

The adapter uses Ubuntu's APT repositories and verifies package ownership with `dpkg-query`. It does not apply the upstream 3.12.13 patch-number floor to Ubuntu's visible interpreter version because distribution packages may preserve an older upstream base version while carrying Ubuntu security backports.

Only `apt-get update` and installation of the two named packages are elevated. The adapter never runs `apt upgrade`, `full-upgrade` or `dist-upgrade`.

### Debian is not Ubuntu

Debian 12 and Debian 13 are explicitly not enabled by this Python 3.12 package adapter. Their default Python branches differ from Ubuntu 24.04, so devkit-wulf does not invent an exact `python3.12` Debian package path merely because both distributions use APT.

A future Debian Python 3.12 source/build or alternative trusted package path requires its own research, source/integrity contract and tests.

## WSL2

Entrypoint:

```sh
./installers/wsl/environments/python-3.12.sh plan
./installers/wsl/environments/python-3.12.sh install --experimental
./installers/wsl/environments/python-3.12.sh verify
```

The WSL adapter first proves it is inside WSL. It then reuses the exact Ubuntu 24.04 Linux implementation rather than duplicating the APT logic.

This means:

- WSL Ubuntu 24.04 uses the same distro package contract as native Ubuntu 24.04;
- a Windows `.exe` is not used inside the WSL distribution;
- Windows-side WSL feature/distribution provisioning remains outside this environment adapter;
- non-Ubuntu WSL distributions fail closed until an exact Python 3.12 adapter exists for them.

## macOS

Entrypoint:

```sh
./installers/macos/environments/python-3.12.sh plan
./installers/macos/environments/python-3.12.sh install --experimental
./installers/macos/environments/python-3.12.sh verify
```

Strategy: Homebrew formula:

```text
python@3.12
```

At the research date, Homebrew publishes `python@3.12` at Python 3.12.13 for supported current macOS bottle targets and also publishes Linux bottles. This adapter deliberately uses the formula only for the macOS installer family; availability of a Linux Homebrew bottle does not cause devkit-wulf to override a distribution-native Linux package strategy automatically.

The adapter sets `HOMEBREW_NO_AUTO_UPDATE=1` for its own operations. If an existing Homebrew `python@3.12` installation is older than the researched security floor, devkit-wulf refuses to silently upgrade it. The operator can update/upgrade Homebrew explicitly and rerun verification.

## Common verification contract

Every active adapter verifies:

1. exact Python major/minor `3.12`;
2. runtime provenance through the selected adapter/package manager;
3. successful creation of an isolated `venv`;
4. `pip --version` from the Python executable inside that temporary environment.

The smoke environment is temporary and cleanup is restricted to a devkit-specific temporary directory pattern.

## Why the implementation differs by operating system

The desired environment is common, but the trusted/native installation mechanism differs:

```text
Python 3.12 shared contract
        │
        ├── Windows ── Python Install Manager runtime tag 3.12
        ├── Ubuntu 24.04 ── APT python3.12 + python3.12-venv
        ├── WSL Ubuntu 24.04 ── same Ubuntu APT payload inside WSL
        └── macOS ── Homebrew python@3.12
```

This is the intended devkit-wulf pattern for versioned environments: **same outcome and verification semantics where possible, system-native installation mechanics where necessary.**

## Upstream / distribution references

- Python version status: https://devguide.python.org/versions/
- Python 3.12 release schedule: https://peps.python.org/pep-0693/
- Python 3.12.13: https://www.python.org/downloads/release/python-31213/
- Python on Windows / Python Install Manager: https://docs.python.org/3/using/windows.html
- Ubuntu 24.04 Python 3.12 venv package: https://packages.ubuntu.com/noble/python3.12-venv
- Homebrew `python@3.12`: https://formulae.brew.sh/formula/python@3.12
- Debian 12 default Python venv package: https://packages.debian.org/bookworm/python3-venv
- Debian 13 default Python venv package: https://packages.debian.org/trixie/python3-venv

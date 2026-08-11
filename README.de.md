# devkit-wulf

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Polski](README.pl.md) | [简体中文](README.cn.md) | [Русский](README.ru.md) | [Español](README.es.md)

Sicherer, manifestgesteuerter Multi-Plattform-Bootstrapper und Orchestrator für Entwicklerumgebungen unter Windows, WSL2, Linux, macOS, BSD sowie ausdrücklich recherchierten erweiterten Unix-Zielsystemen.

> **Status:** Pre-1.0. Plattform-/Umgebungskombinationen bleiben `experimental`, bis die erforderlichen CI- und Zielsystem-Gates bestanden sind. Vorhandene Adapter werden nicht automatisch als unterstützte Plattformen beworben.

Den auditierten Ist-/Sollstand vom **11.08.2026** enthält [`docs/REPOSITORY-STATUS.md`](docs/REPOSITORY-STATUS.md).

## Architektur

`devkit-wulf` trennt Host-/Architekturerkennung, Quellen- und Paketmanagerwahl, Umgebungsmetadaten, Installationsstrategie, nicht verändernde Planung, Integritätsprüfung, Verifikation, Zustands-/Ownership-Daten und CI-/Release-Gates.

Gemeinsame versionspezifische Verträge liegen unter `environments/`. Die **release-facing** Einstiegspunkte liegen unter `installers/` und sind systemnativ. `bin/` enthält interne generische Orchestrierungskerne während der Migration; diese sind nicht als universelles Cross-OS-Releaseformat zu verstehen.

Siehe [`docs/installer-architecture.md`](docs/installer-architecture.md).

## Schnellstart

### Natives Linux

```sh
./bootstrap/linux.sh
./installers/linux/devkit-wulf.sh detect
./installers/linux/devkit-wulf.sh list
./installers/linux/devkit-wulf.sh plan python
./installers/linux/devkit-wulf.sh install python --experimental
./installers/linux/devkit-wulf.sh verify python
./installers/linux/devkit-wulf.sh doctor
```

Der native Linux-Einstiegspunkt lehnt WSL ab.

### macOS

```sh
./bootstrap/macos.sh
./installers/macos/devkit-wulf.sh detect
./installers/macos/devkit-wulf.sh plan python
```

### BSD / Solaris / illumos / AIX

```sh
./bootstrap/bsd.sh
./installers/bsd/devkit-wulf.sh detect

./bootstrap/solaris.sh
./installers/solaris/devkit-wulf.sh detect

./bootstrap/aix.sh
./installers/aix/devkit-wulf.sh detect
```

Ein erfolgreicher Bootstrap bedeutet nicht, dass Umgebungs-Support promoted wurde.

### Windows PowerShell

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\bootstrap\windows.ps1
.\installers\windows\devkit-wulf.ps1 detect
.\installers\windows\devkit-wulf.ps1 list
.\installers\windows\devkit-wulf.ps1 plan python
.\installers\windows\devkit-wulf.ps1 install python -Experimental
.\installers\windows\devkit-wulf.ps1 verify python
.\installers\windows\devkit-wulf.ps1 doctor
```

Windows PowerShell 5.1 und PowerShell 7 werden akzeptiert. WinGet-Installationen prüfen vorhandene exakte Paket-IDs vor einer Mutation.

### WSL2

Innerhalb der gewählten WSL-Distribution wird der WSL-Einstiegspunkt verwendet:

```sh
./bootstrap/linux.sh
./installers/wsl/devkit-wulf.sh detect
./installers/wsl/devkit-wulf.sh plan python
```

`devkit-wulf` erstellt nicht stillschweigend eine WSL-Distribution und konvertiert WSL1 nicht automatisch. Windows-seitige Systemänderungen benötigen explizite Planung und `-AllowSystemChange`.

## Befehle

```text
devkit-wulf detect
devkit-wulf list
devkit-wulf list --supported
devkit-wulf list --platform <platform>
devkit-wulf plan <environment>
devkit-wulf install <environment> [--experimental]
devkit-wulf verify <environment>
devkit-wulf remove <environment>
devkit-wulf install profile:<name> [--experimental]
devkit-wulf doctor
```

`plan` verändert den Host nicht. `install` lehnt `unsupported` ab und verlangt für experimentelle Pfade eine ausdrückliche Freigabe. Die generischen Kerne besitzen derzeit noch keine vollständige `--version`-/`--target native|wsl:<distro>`-Auflösung; siehe Issue #4.

## Versionspezifische systemnative Selektoren

Auditstand **11.08.2026**:

| Selektor | Linux | WSL2 | macOS | Windows |
| --- | --- | --- | --- | --- |
| `python@3.12` | experimental geroutet | experimental geroutet | experimental geroutet | experimental geroutet |
| `go@stable` | experimental geroutet | experimental geroutet | experimental geroutet | experimental geroutet |
| `rust@stable` | experimental geroutet | experimental geroutet | experimental geroutet | Adapter vorhanden, zentrale Route gesperrt |
| `flutter@stable` | experimental geroutet | unsupported | experimental geroutet | experimental geroutet (amd64) |
| `kubectl@stable` | nicht zentral geroutet | nicht zentral geroutet | direkter nativer Adapter vorhanden | direkter nativer Adapter vorhanden |

Diese Tabelle beschreibt Implementierung/Routing und **keinen promoted Support**. Der Go-Windows-Workflow besitzt noch eine veraltete Fail-Closed-Annahme (Issue #35). Windows-Rust bleibt dagegen bewusst auf zentraler Routing-Ebene gesperrt, obwohl ein nativer Adapter existiert.

## Umgebungen

### Basis und Sprachen

`base`, `cpp`, `python`, `node`, `deno`, `bun`, `java`, `dotnet`, `go`, `rust`, `php`, `ruby`

### Editoren und IDEs

`vscode`, `visualstudio`, `jetbrains`, `eclipse`

### Mobile / Plattform-SDKs

`android`, `flutter`, `xcode`

### Container / Infrastruktur

`docker`, `podman`, `kubectl`, `opentofu`

**Bekannter Contract-Drift:** `profiles/profiles.json` und `tests/validate_manifests.py` referenzieren noch `apple`, während der kanonische Katalog `xcode` definiert. Siehe Issue #34.

## Profile

`minimal`, `web`, `backend`, `systems`, `mobile`, `devops`, `full`, `wsl-stable`, `wsl-rolling`

`full` aktiviert experimentelle Umgebungen nicht selbstständig. Unbekannte, `unsupported`- oder `target-only`-Einträge dürfen nicht stillschweigend in Installationen umgewandelt werden.

## Sicherheitsmodell

Die verbindlichen Regeln stehen in [`AGENTS.md`](AGENTS.md). Dazu gehören insbesondere:

- kein stiller Unsupported-Fallback;
- keine automatische `curl | sh`-/`irm | iex`-Ausführung;
- HTTPS-/Quellen- und Integritätsprüfungen für überprüfte Artefaktpfade;
- Staging vor Mutation und Schutz vor Traversal/Symlink/Reparse-Point-Angriffen;
- keine Übernahme fremder/unverwalteter Installationsziele;
- keine implizite permanente PATH-Mutation in den überprüften user-local Artefaktadaptern;
- begrenzte Privilegien;
- fail-closed bei unsicherer Deinstallation;
- getrennte Support-Promotion erst nach vollständigen Gates.

Ownership-Marker allein erfüllen noch nicht den vollständigen Removal-Gate; siehe Issue #3.

## Repository-Struktur

```text
AGENTS.md               Governance-Vertrag und verpflichtende Gates
installers/             release-facing systemnative Einstiegspunkte/Adapter
environments/           gemeinsame versionspezifische Umgebungsverträge
bin/                    interne generische Orchestrierungskerne
bootstrap/              minimale Host-Bootstrap-Skripte
manifests/              Plattform-/Umgebungs-/Artefakt-/Repository-Verträge
profiles/               kombinierbare Umgebungsauswahlen
research/               datierte Upstream-Recherche
scripts/                Validierungs-/Security-Hilfen
tests/                  semantische Validatoren und Offline-Fixtures
.github/workflows/       CI-Gates
```

## Validierungs- und Release-Stand

Die Testmatrix enthält umfangreiche Offline-Fixtures und semantische Validatoren. Der zuletzt auditierte GitHub-Actions-Lauf wurde jedoch **vor Runner-Start** durch einen externen Account-/Billing-Zustand blockiert. Daraus wird weder „CI grün“ noch ein Produkt-Testfehler abgeleitet.

Es existieren derzeit keine GitHub Releases und keine Git-Tags. Release-Checksummen/SBOM bleiben über Issue #6 offen; Extended-Unix-Zielvalidierung über Issue #5.

## Dokumentation

- [Auditierter Repository-Status](docs/REPOSITORY-STATUS.md)
- [Installer-Architektur](docs/installer-architecture.md)
- [Systemnative Einstiegspunkte](installers/README.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)
- [Beitragsrichtlinien](CONTRIBUTING.md)
- [Support](SUPPORT.md)
- [Sicherheit](SECURITY.md)
- [Übersetzungsrichtlinie](docs/TRANSLATIONS.md)

## Projekt unterstützen

<a href="https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U" target="_blank"><img src="https://www.paypalobjects.com/en_US/DK/i/btn/btn_donateCC_LG.gif" alt="Mit PayPal spenden" /></a>

[Mit PayPal spenden](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

[![PayPal-Spenden-QR-Code](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

## Lizenz

MIT — siehe [`LICENSE`](LICENSE).

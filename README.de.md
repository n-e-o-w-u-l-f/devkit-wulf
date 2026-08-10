# devkit-wulf

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Polski](README.pl.md) | [简体中文](README.cn.md) | [Русский](README.ru.md) | [Español](README.es.md)

Sicherer, manifestgesteuerter Multi-Plattform-Bootstrapper und Orchestrator für Entwicklerumgebungen unter Windows, WSL2, Linux, macOS, BSD sowie ausdrücklich recherchierten erweiterten Unix-Zielsystemen.

> **Status:** Pre-1.0-Bootstrap. Plattform-/Umgebungskombinationen bleiben `experimental`, bis die erforderlichen CI- oder Zielsystem-Gates erfolgreich durchlaufen wurden. Das Repository weist bewusst keine ungeprüften Kombinationen als unterstützt aus.

## Design

`devkit-wulf` trennt die Verantwortlichkeiten für:

- Host- und Architekturerkennung;
- Auswahl des Paketmanagers;
- Umgebungsmetadaten und Support-Richtlinien;
- Installationsstrategie;
- nicht verändernde Planung;
- Mutation und Privilegienbehandlung;
- Verifikation;
- Zustandsverfolgung und Rollback-Bewusstsein;
- CI-/Security-Gates.

Supportstatus und Ausführungsstrategie werden unabhängig voneinander modelliert. Eine Kombination kann daher `support: experimental` sein und gleichzeitig `strategy: package-manager`, `winget`, `official-script`, `official-archive`, `source`, `vm`, `container`, `wsl2` oder `xcode` verwenden.

## Schnellstart

### Linux / macOS / BSD / Unix

```sh
./bootstrap/linux.sh        # Linux / WSL2
./bootstrap/macos.sh        # macOS
./bootstrap/bsd.sh          # FreeBSD/OpenBSD/NetBSD/DragonFly
./bootstrap/solaris.sh      # Solaris/illumos
./bootstrap/aix.sh          # AIX

./bin/devkit-wulf detect
./bin/devkit-wulf list
./bin/devkit-wulf plan python
./bin/devkit-wulf install python --experimental
./bin/devkit-wulf verify python
./bin/devkit-wulf doctor
```

Die Bootstrap-Skripte installieren nur die kleinen Parser-/Tooling-Voraussetzungen, die der Orchestrator benötigt. Entwicklerprofile werden dadurch nicht installiert.

### Windows PowerShell

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\bootstrap\windows.ps1
.\bin\devkit-wulf.ps1 detect
.\bin\devkit-wulf.ps1 list
.\bin\devkit-wulf.ps1 plan python
.\bin\devkit-wulf.ps1 install python -Experimental
.\bin\devkit-wulf.ps1 verify python
.\bin\devkit-wulf.ps1 doctor
```

Der native Orchestrator akzeptiert Windows PowerShell 5.1 und PowerShell 7. WinGet-basierte Installationen werden vor einer Änderung geprüft, damit bereits installierte exakte Paket-IDs nicht absichtlich erneut installiert werden.

### WSL2

Führe die Linux-CLI innerhalb der gewählten WSL-Distribution aus. WSL-Distributionen werden unabhängig vom Windows-Host erkannt. `devkit-wulf` erstellt niemals stillschweigend eine WSL-Distribution und konvertiert WSL1 nicht automatisch zu WSL2.

Um eine Windows-seitige WSL-Änderung zunächst zu prüfen:

```powershell
.\bootstrap\windows.ps1 -PlanWSL2 -Distribution Debian
```

Eine Änderung an WSL-Features oder Distributionen benötigt zusätzlich eine erhöhte Shell und `-AllowSystemChange`.

Projekte für Linux-Werkzeuge sollten innerhalb von WSL2 im Linux-Dateisystem liegen. Native Windows-Projekte sollten auf der Windows-Seite verbleiben; dateisystemübergreifende I/O wird bewusst nicht als Standardlayout behandelt.

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

Unter nativem Windows werden die entsprechenden PowerShell-Schalter `-Experimental` und `-AcceptRemoteScript` verwendet.

`plan` verändert das System nicht. `install` lehnt `unsupported`-Kombinationen ab und verlangt eine ausdrückliche Experimental-Freigabe für Kombinationen, die noch nicht alle Support-Gates bestanden haben. Strategien ohne verifizierten dedizierten Adapter schlagen kontrolliert fehl, statt einen Installer zu erraten.

## Initiale Umgebungen

### Basis und Sprachen

- `base`
- `cpp`
- `python`
- `node`
- `deno`
- `bun`
- `java`
- `dotnet`
- `go`
- `rust`
- `php`
- `ruby`

### Editoren und IDEs

- `vscode`
- `visualstudio`
- `jetbrains`
- `eclipse`

### Mobile / Plattform-SDKs

- `android`
- `flutter`
- `apple`

### Container / Infrastruktur

- `docker`
- `podman`
- `kubectl`
- `opentofu`

## Profile

- `minimal`
- `web`
- `backend`
- `systems`
- `mobile`
- `devops`
- `full`
- `wsl-stable`
- `wsl-rolling`

Das Profil `full` aktiviert `experimental`-Umgebungen niemals selbstständig. `unsupported`- und `target-only`-Einträge werden niemals in Host-Installationen umgewandelt.

## Plattformmodell

Primäre Implementierungsziele:

- Windows 11 und gewartete Windows-10-Clients, x64/ARM64 soweit die jeweilige Umgebung dies unterstützt;
- WSL2 mit Debian, Ubuntu, Arch Linux, openSUSE und Kali;
- Debian/Ubuntu/Mint/Kali/Raspberry Pi OS;
- Arch/Manjaro;
- Fedora/RHEL/Rocky/Alma;
- openSUSE;
- Alpine;
- macOS Intel und Apple Silicon.

Forschungs-/Validierungsziele:

- FreeBSD, OpenBSD, NetBSD, DragonFly BSD;
- illumos, Oracle Solaris, AIX.

Erweiterte Unix-Einträge bleiben `experimental` oder `target-only`, bis sie auf autoritativen Zielsystemen validiert wurden. Cross-Compilation-Fähigkeiten werden getrennt vom Host-Support modelliert.

## Sicherheitsmodell

Die Implementierung folgt den Gates in [`AGENTS.md`](AGENTS.md). Insbesondere gilt:

- kein stiller Fallback auf nicht unterstützte Kombinationen;
- keine automatische Ausführung von `curl | sh` / `irm | iex`;
- Herkunftsangaben für Quellen werden in Manifesten dokumentiert;
- Paketmanager und offizielle Herstellerpfade werden bevorzugt;
- Remote-Skripte müssen vor der Ausführung heruntergeladen und geprüft werden;
- Prüfsummen-/Signaturabweichungen führen zu einem harten Fehler, wenn Upstream entsprechende Integritätsdaten bereitstellt;
- Rechteerhöhung ist auf tatsächlich erforderliche Operationen begrenzt;
- `plan` verändert den Host nicht;
- destruktive Deinstallation wird verweigert, wenn Eigentumsverhältnisse nicht sicher bestimmt werden können;
- Ausschlüsse für Windows Server werden unabhängig vom Windows-Client-Support ausgewertet, wenn Upstream dies verlangt.

## Repository-Struktur

```text
AGENTS.md               Governance-Vertrag und verpflichtende Gates
bin/                    POSIX- und PowerShell-Orchestratoren
bootstrap/              minimale Host-Bootstrap-Skripte
manifests/              Plattform-/Umgebungskatalog und Schema
profiles/               kombinierbare Umgebungsauswahlen
research/               datierte Upstream-Support-/Quellenrecherche
scripts/                Validierungs-/Security-Hilfen
tests/                  Manifest- und CLI-Tests
.github/workflows/       CI-Gates
```

## Aktuelle Automatisierungsgrenze

Paketmanager- und ausgewählte `official-script`-Strategien verfügen über ausführbare Adapter. `official-archive`, produktspezifische `manual`-Strategien, Source-Builds sowie VM- und Container-Strategien werden in Plänen dargestellt, schlagen jedoch bewusst kontrolliert fehl, bis Download-, Integritäts-, Eigentums-, PATH- und Deinstallationsverträge pro Produkt implementiert sind.

Diese Grenze verhindert, dass eine breite Plattformmatrix zu einer ungeprüften Sammlung von Download-Befehlen wird.

## Upstream-Recherche

Die initiale Supportmatrix wurde am **10.08.2026** anhand primärer Upstream-Dokumentation aktualisiert. Siehe [`research/upstream-sources.md`](research/upstream-sources.md). Runtime-Versionen und EOL-Informationen werden bewusst nicht als dauerhaft angenommen; Manifeste enthalten Recherchedaten und müssen vor versionssensitiven Änderungen erneut validiert werden.

Die empfohlene Host-/Domain-Strategie pro Plattform und Umgebung steht in [`docs/platform-strategy.md`](docs/platform-strategy.md). Der phasenweise Implementierungs- und Promotion-Status wird in [`ROADMAP.md`](ROADMAP.md) verfolgt.

## Dokumentation und Community

- [Beitragsrichtlinien](CONTRIBUTING.md)
- [Support- und Fehlerberichtsleitfaden](SUPPORT.md)
- [Sicherheitsrichtlinie](SECURITY.md)
- [Übersetzungsrichtlinie](docs/TRANSLATIONS.md)
- [Roadmap](ROADMAP.md)

## Projekt unterstützen

Wenn `devkit-wulf` für dich nützlich ist, kannst du die weitere Entwicklung über PayPal unterstützen:

<a href="https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U" target="_blank"><img src="https://www.paypalobjects.com/en_US/DK/i/btn/btn_donateCC_LG.gif" alt="Mit PayPal spenden" title="PayPal - The safer, easier way to pay online!" /></a>

[Mit PayPal spenden](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

Scanne oder klicke auf den QR-Code, um dieselbe PayPal-Spendenseite zu öffnen:

[![PayPal-Spenden-QR-Code](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

## Lizenz

MIT — siehe [`LICENSE`](LICENSE).

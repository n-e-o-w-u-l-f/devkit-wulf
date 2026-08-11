# devkit-wulf

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Polski](README.pl.md) | [简体中文](README.cn.md) | [Русский](README.ru.md) | [Español](README.es.md)

Bezpieczny, sterowany manifestami, wieloplatformowy bootstrapper i orkiestrator środowisk programistycznych dla Windows, WSL2, Linux, macOS, BSD oraz jawnie zbadanych rozszerzonych systemów Unix.

> **Status:** pre-1.0. Kombinacje platforma/środowisko pozostają `experimental`, dopóki nie przejdą wymaganych bramek CI i walidacji na systemach docelowych. Samo istnienie adaptera nie oznacza promowanego wsparcia.

Audytowany stan z **2026-08-11** opisuje [`docs/REPOSITORY-STATUS.md`](docs/REPOSITORY-STATUS.md).

## Architektura

`devkit-wulf` rozdziela wykrywanie hosta/architektury, wybór źródeł i menedżera pakietów, kontrakty środowisk, planowanie bez modyfikacji, integralność, weryfikację, stan/własność oraz bramki CI/release.

Wspólne kontrakty wersjonowane znajdują się w `environments/`. Punkty wejścia **release-facing** znajdują się w `installers/` i są natywne dla danego systemu. `bin/` zawiera wewnętrzne, ogólne rdzenie orkiestracji w trakcie migracji i nie jest uniwersalnym formatem wykonywalnym dla wszystkich systemów.

## Szybki start

### Natywny Linux

```sh
./bootstrap/linux.sh
./installers/linux/devkit-wulf.sh detect
./installers/linux/devkit-wulf.sh list
./installers/linux/devkit-wulf.sh plan python
./installers/linux/devkit-wulf.sh install python --experimental
./installers/linux/devkit-wulf.sh verify python
```

### macOS

```sh
./bootstrap/macos.sh
./installers/macos/devkit-wulf.sh detect
./installers/macos/devkit-wulf.sh plan python
```

### Windows PowerShell

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\bootstrap\windows.ps1
.\installers\windows\devkit-wulf.ps1 detect
.\installers\windows\devkit-wulf.ps1 list
.\installers\windows\devkit-wulf.ps1 plan python
.\installers\windows\devkit-wulf.ps1 install python -Experimental
.\installers\windows\devkit-wulf.ps1 verify python
```

### WSL2

```sh
./bootstrap/linux.sh
./installers/wsl/devkit-wulf.sh detect
./installers/wsl/devkit-wulf.sh plan python
```

`devkit-wulf` nie tworzy po cichu dystrybucji WSL i nie konwertuje automatycznie WSL1 do WSL2. Zmiany systemowe po stronie Windows wymagają jawnego planu i `-AllowSystemChange`.

## Wersjonowane selektory natywne

Stan audytu **2026-08-11**:

| Selektor | Linux | WSL2 | macOS | Windows |
| --- | --- | --- | --- | --- |
| `python@3.12` | eksperymentalna trasa | eksperymentalna trasa | eksperymentalna trasa | eksperymentalna trasa |
| `go@stable` | eksperymentalna trasa | eksperymentalna trasa | eksperymentalna trasa | eksperymentalna trasa |
| `rust@stable` | eksperymentalna trasa | eksperymentalna trasa | eksperymentalna trasa | adapter istnieje, centralna trasa zablokowana |
| `flutter@stable` | eksperymentalna trasa | unsupported | eksperymentalna trasa | eksperymentalna trasa (amd64) |
| `kubectl@stable` | brak centralnej trasy | brak centralnej trasy | bezpośredni adapter natywny | bezpośredni adapter natywny |

Tabela opisuje implementację/routing, **nie promowane wsparcie**. Workflow Go dla Windows nadal zawiera przestarzałe oczekiwanie fail-closed (issue #35). Windows Rust ma natywny adapter, lecz centralny selektor pozostaje celowo zablokowany.

## Środowiska i profile

Główne środowiska:

`base`, `cpp`, `python`, `node`, `deno`, `bun`, `java`, `dotnet`, `go`, `rust`, `php`, `ruby`, `vscode`, `visualstudio`, `jetbrains`, `eclipse`, `android`, `flutter`, `xcode`, `docker`, `podman`, `kubectl`, `opentofu`.

Profile:

`minimal`, `web`, `backend`, `systems`, `mobile`, `devops`, `full`, `wsl-stable`, `wsl-rolling`.

**Znany drift kontraktu:** `profiles/profiles.json` oraz `tests/validate_manifests.py` nadal używają starego identyfikatora `apple`, podczas gdy katalog kanoniczny definiuje `xcode`. Zobacz issue #34.

## Model bezpieczeństwa

Obowiązujące reguły znajdują się w [`AGENTS.md`](AGENTS.md), w tym:

- brak cichego fallbacku do niewspieranych kombinacji;
- brak automatycznego `curl | sh` / `irm | iex`;
- kontrole HTTPS/źródła/integralności dla zweryfikowanych ścieżek artefaktów;
- staging przed modyfikacją oraz ochrona przed traversal/symlink/reparse-point;
- odmowa przejęcia obcego lub niezarządzanego katalogu docelowego;
- brak niejawnej trwałej modyfikacji PATH w zweryfikowanych adapterach user-local;
- ograniczone uprawnienia;
- fail-closed dla usuwania bez pewnego dowodu własności;
- osobna promocja wsparcia dopiero po przejściu wszystkich bramek.

Bezpieczne usuwanie pozostaje otwarte w issue #3.

## Stan CI i release

Repozytorium zawiera rozbudowane offline fixtures Shell/PowerShell oraz semantyczne walidatory Python. Ostatni audytowany GitHub Actions run został jednak zablokowany **przed uruchomieniem runnera** przez zewnętrzny stan konta/billingu. Nie jest to ani zielone CI, ani wynik testu produktu.

Obecnie nie ma GitHub Releases ani tagów Git. Checksumy/SBOM release są otwarte w issue #6, a walidacja rozszerzonych systemów Unix w issue #5.

## Dokumentacja

- [Audytowany stan repozytorium](docs/REPOSITORY-STATUS.md)
- [Architektura instalatorów](docs/installer-architecture.md)
- [Natywne punkty wejścia](installers/README.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)
- [Współtworzenie](CONTRIBUTING.md)
- [Wsparcie](SUPPORT.md)
- [Bezpieczeństwo](SECURITY.md)
- [Polityka tłumaczeń](docs/TRANSLATIONS.md)

## Wesprzyj projekt

[Wesprzyj przez PayPal](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

[![Kod QR darowizny PayPal](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

## Licencja

MIT — zobacz [`LICENSE`](LICENSE).

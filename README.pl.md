# devkit-wulf

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Polski](README.pl.md) | [简体中文](README.cn.md) | [Русский](README.ru.md) | [Español](README.es.md)

Bezpieczny, sterowany manifestami, wieloplatformowy bootstrapper i orkiestrator środowisk programistycznych dla Windows, WSL2, Linux, macOS, BSD oraz jawnie zbadanych rozszerzonych systemów Unix.

> **Status:** bootstrap pre-1.0. Kombinacje platforma/środowisko pozostają `experimental`, dopóki nie przejdą wymaganych bramek CI lub walidacji na systemie docelowym. Repozytorium celowo nie deklaruje niezweryfikowanych kombinacji jako wspieranych.

## Projekt

`devkit-wulf` rozdziela odpowiedzialności za:

- wykrywanie hosta i architektury;
- wybór menedżera pakietów;
- metadane środowiska i politykę wsparcia;
- strategię instalacji;
- planowanie bez modyfikacji;
- modyfikacje i obsługę uprawnień;
- weryfikację;
- śledzenie stanu i świadomość rollbacku;
- bramki CI i bezpieczeństwa.

Status wsparcia i strategia wykonania są modelowane niezależnie. Kombinacja może więc mieć `support: experimental`, korzystając jednocześnie ze `strategy: package-manager`, `winget`, `official-script`, `official-archive`, `source`, `vm`, `container`, `wsl2` lub `xcode`.

## Szybki start

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

Skrypty bootstrap instalują wyłącznie niewielkie zależności parsera/narzędzi wymagane przez orkiestrator. Nie instalują profili programistycznych.

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

Natywny orkiestrator obsługuje Windows PowerShell 5.1 i PowerShell 7. Instalacje oparte na WinGet są sprawdzane przed zmianą systemu, aby dokładne identyfikatory już zainstalowanych pakietów nie były celowo instalowane ponownie.

### WSL2

Uruchom CLI Linux wewnątrz wybranej dystrybucji WSL. Dystrybucje WSL są wykrywane niezależnie od hosta Windows. `devkit-wulf` nigdy nie tworzy po cichu dystrybucji WSL ani automatycznie nie konwertuje WSL1 do WSL2.

Aby najpierw sprawdzić plan zmiany WSL po stronie Windows:

```powershell
.\bootstrap\windows.ps1 -PlanWSL2 -Distribution Debian
```

Zmiana funkcji lub dystrybucji WSL wymaga dodatkowo podwyższonych uprawnień i parametru `-AllowSystemChange`.

Projekty używane przez narzędzia Linux powinny zwykle znajdować się w systemie plików Linux wewnątrz WSL2. Natywne projekty Windows powinny pozostać po stronie Windows; operacje I/O pomiędzy systemami plików nie są traktowane jako domyślny układ.

## Polecenia

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

W natywnym Windows używane są odpowiadające parametry PowerShell `-Experimental` i `-AcceptRemoteScript`.

`plan` nie modyfikuje systemu. `install` odrzuca kombinacje `unsupported` i wymaga jawnej zgody na tryb eksperymentalny dla kombinacji, które nie przeszły jeszcze wszystkich bramek wsparcia. Strategie bez zweryfikowanego dedykowanego adaptera kończą się bezpiecznym błędem zamiast zgadywać instalator.

## Początkowe środowiska

### Podstawa i języki

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

### Edytory i IDE

- `vscode`
- `visualstudio`
- `jetbrains`
- `eclipse`

### Mobile / SDK platform

- `android`
- `flutter`
- `apple`

### Kontenery / infrastruktura

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

Profil `full` nigdy samodzielnie nie włącza środowisk `experimental`. Wpisy `unsupported` i `target-only` nigdy nie są zamieniane na instalacje hosta.

## Model platform

Główne cele implementacji:

- Windows 11 i obsługiwane wersje klienckie Windows 10, x64/ARM64 tam, gdzie dane środowisko to wspiera;
- WSL2 z Debian, Ubuntu, Arch Linux, openSUSE i Kali;
- Debian/Ubuntu/Mint/Kali/Raspberry Pi OS;
- Arch/Manjaro;
- Fedora/RHEL/Rocky/Alma;
- openSUSE;
- Alpine;
- macOS Intel i Apple Silicon.

Cele badawcze/walidacyjne:

- FreeBSD, OpenBSD, NetBSD, DragonFly BSD;
- illumos, Oracle Solaris, AIX.

Rozszerzone wpisy Unix pozostają `experimental` lub `target-only`, dopóki nie zostaną zwalidowane na autorytatywnych systemach docelowych. Możliwości cross-kompilacji są modelowane oddzielnie od wsparcia hosta.

## Model bezpieczeństwa

Implementacja stosuje bramki z [`AGENTS.md`](AGENTS.md). W szczególności:

- brak cichego fallbacku do niewspieranych kombinacji;
- brak automatycznego wykonywania `curl | sh` / `irm | iex`;
- pochodzenie źródeł jest zapisywane w manifestach;
- preferowane są menedżery pakietów i oficjalne kanały dostawców;
- skrypty zdalne muszą zostać pobrane i sprawdzone przed wykonaniem;
- niezgodność sum kontrolnych/podpisów powoduje twardy błąd, gdy upstream udostępnia dane integralności;
- podnoszenie uprawnień ogranicza się do operacji, które faktycznie tego wymagają;
- `plan` nigdy nie modyfikuje hosta;
- destrukcyjna dezinstalacja jest odrzucana, jeśli nie można bezpiecznie ustalić własności zasobów;
- wykluczenia dla Windows Server są oceniane niezależnie od wsparcia klienta Windows, gdy wymaga tego upstream.

## Struktura repozytorium

```text
AGENTS.md               kontrakt zarządzania i obowiązkowe bramki
bin/                    orkiestratory POSIX i PowerShell
bootstrap/              minimalne skrypty bootstrap hosta
manifests/              katalog platform/środowisk i schemat
profiles/               komponowalne zestawy środowisk
research/               datowane badania źródeł i wsparcia upstream
scripts/                narzędzia walidacji/bezpieczeństwa
tests/                  testy manifestów i CLI
.github/workflows/       bramki CI
```

## Aktualna granica automatyzacji

Strategie menedżerów pakietów oraz wybrane strategie `official-script` mają wykonywalne adaptery. Strategie `official-archive`, specyficzne dla produktów `manual`, kompilacje ze źródeł, VM i kontenery są przedstawiane w planach, ale celowo kończą się bezpiecznym błędem, dopóki dla danego produktu nie zostaną wdrożone kontrakty pobierania, integralności, własności, PATH i dezinstalacji.

Granica ta zapobiega przekształceniu szerokiej macierzy platform w niezweryfikowaną kolekcję poleceń pobierania.

## Badania upstream

Początkowa macierz wsparcia została odświeżona **2026-08-10** na podstawie pierwotnej dokumentacji upstream. Zobacz [`research/upstream-sources.md`](research/upstream-sources.md). Wersje runtime i informacje EOL celowo nie są uznawane za trwałe; manifesty zawierają daty badań i muszą być ponownie walidowane przed zmianami zależnymi od wersji.

Zalecana strategia host/domena dla platform i środowisk znajduje się w [`docs/platform-strategy.md`](docs/platform-strategy.md). Etapowy stan implementacji i promocji jest śledzony w [`ROADMAP.md`](ROADMAP.md).

## Dokumentacja i społeczność

- [Zasady współtworzenia](CONTRIBUTING.md)
- [Wsparcie i zgłaszanie problemów](SUPPORT.md)
- [Polityka bezpieczeństwa](SECURITY.md)
- [Polityka tłumaczeń](docs/TRANSLATIONS.md)
- [Plan rozwoju](ROADMAP.md)

## Wesprzyj projekt

Jeżeli `devkit-wulf` jest dla Ciebie przydatny, możesz wesprzeć dalszy rozwój przez PayPal:

<a href="https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U" target="_blank"><img src="https://www.paypalobjects.com/en_US/DK/i/btn/btn_donateCC_LG.gif" alt="Wesprzyj przez PayPal" title="PayPal - The safer, easier way to pay online!" /></a>

[Wesprzyj przez PayPal](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

Zeskanuj lub kliknij kod QR, aby otworzyć tę samą stronę darowizny PayPal:

[![Kod QR darowizny PayPal](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

## Licencja

MIT — zobacz [`LICENSE`](LICENSE).

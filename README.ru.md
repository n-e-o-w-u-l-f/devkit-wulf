# devkit-wulf

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Polski](README.pl.md) | [简体中文](README.cn.md) | [Русский](README.ru.md) | [Español](README.es.md)

Безопасный, управляемый манифестами многоплатформенный bootstrapper и оркестратор сред разработки для Windows, WSL2, Linux, macOS, BSD и явно исследованных расширенных Unix-систем.

> **Статус:** bootstrap до версии 1.0. Комбинации платформа/среда остаются `experimental`, пока не пройдут требуемые CI-gates или проверку на целевой системе. Репозиторий намеренно не объявляет непроверенные комбинации поддерживаемыми.

## Архитектура

`devkit-wulf` разделяет ответственность за:

- определение хоста и архитектуры;
- выбор менеджера пакетов;
- метаданные окружения и политику поддержки;
- стратегию установки;
- планирование без изменений системы;
- изменения и управление привилегиями;
- проверку;
- отслеживание состояния и учёт отката;
- CI- и security-gates.

Статус поддержки и стратегия выполнения моделируются независимо. Поэтому комбинация может иметь `support: experimental`, одновременно используя `strategy: package-manager`, `winget`, `official-script`, `official-archive`, `source`, `vm`, `container`, `wsl2` или `xcode`.

## Быстрый старт

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

Bootstrap-скрипты устанавливают только небольшие зависимости парсера/инструментария, необходимые оркестратору. Профили разработки они не устанавливают.

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

Нативный оркестратор поддерживает Windows PowerShell 5.1 и PowerShell 7. Установки через WinGet проверяются до изменения системы, чтобы уже установленные точные ID пакетов не переустанавливались намеренно.

### WSL2

Запускайте Linux CLI внутри выбранного дистрибутива WSL. Дистрибутивы WSL определяются независимо от Windows-хоста. `devkit-wulf` никогда не создаёт дистрибутив WSL без явного запроса и не преобразует WSL1 в WSL2 автоматически.

Чтобы сначала проверить план изменения WSL со стороны Windows:

```powershell
.\bootstrap\windows.ps1 -PlanWSL2 -Distribution Debian
```

Изменение функций или дистрибутивов WSL дополнительно требует повышенных прав и параметра `-AllowSystemChange`.

Проекты для Linux-инструментов внутри WSL2 обычно следует хранить в Linux-файловой системе. Нативные Windows-проекты должны оставаться на стороне Windows; межфайловый I/O намеренно не считается стандартной схемой.

## Команды

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

В нативном Windows используются эквивалентные параметры PowerShell `-Experimental` и `-AcceptRemoteScript`.

`plan` не изменяет систему. `install` отклоняет комбинации `unsupported` и требует явного экспериментального выбора для комбинаций, которые ещё не прошли все gates поддержки. Стратегии без проверенного специализированного адаптера завершаются безопасной ошибкой вместо попытки угадать установщик.

## Начальные среды

### Базовые инструменты и языки

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

### Редакторы и IDE

- `vscode`
- `visualstudio`
- `jetbrains`
- `eclipse`

### Mobile / SDK платформ

- `android`
- `flutter`
- `apple`

### Контейнеры / инфраструктура

- `docker`
- `podman`
- `kubectl`
- `opentofu`

## Профили

- `minimal`
- `web`
- `backend`
- `systems`
- `mobile`
- `devops`
- `full`
- `wsl-stable`
- `wsl-rolling`

Профиль `full` никогда сам не включает `experimental`-среды. Записи `unsupported` и `target-only` никогда не преобразуются в установки на хост.

## Модель платформ

Основные цели реализации:

- Windows 11 и обслуживаемые клиентские версии Windows 10, x64/ARM64 там, где это поддерживает конкретная среда;
- WSL2 с Debian, Ubuntu, Arch Linux, openSUSE и Kali;
- Debian/Ubuntu/Mint/Kali/Raspberry Pi OS;
- Arch/Manjaro;
- Fedora/RHEL/Rocky/Alma;
- openSUSE;
- Alpine;
- macOS Intel и Apple Silicon.

Цели исследования/валидации:

- FreeBSD, OpenBSD, NetBSD, DragonFly BSD;
- illumos, Oracle Solaris, AIX.

Расширенные Unix-записи остаются `experimental` или `target-only`, пока не будут проверены на авторитетных целевых системах. Возможности кросс-компиляции моделируются отдельно от поддержки хоста.

## Модель безопасности

Реализация следует gates из [`AGENTS.md`](AGENTS.md). В частности:

- нет скрытого fallback на неподдерживаемые комбинации;
- нет автоматического выполнения `curl | sh` / `irm | iex`;
- происхождение источников фиксируется в манифестах;
- приоритет отдается пакетным менеджерам и официальным каналам поставщиков;
- удалённые скрипты должны быть скачаны и проверены до выполнения;
- несовпадение checksum/подписи приводит к жёсткой ошибке, если upstream предоставляет данные целостности;
- повышение привилегий ограничено только операциями, которым оно действительно необходимо;
- `plan` никогда не изменяет хост;
- разрушительное удаление запрещено, если нельзя безопасно установить принадлежность ресурсов;
- исключения Windows Server оцениваются независимо от поддержки Windows client, если этого требует upstream.

## Структура репозитория

```text
AGENTS.md               контракт управления и обязательные gates
bin/                    POSIX- и PowerShell-оркестраторы
bootstrap/              минимальные bootstrap-скрипты хоста
manifests/              каталог платформ/сред и схема
profiles/               составные наборы сред
research/               датированные исследования поддержки/источников upstream
scripts/                инструменты проверки/безопасности
tests/                  тесты манифестов и CLI
.github/workflows/       CI-gates
```

## Текущая граница автоматизации

Стратегии пакетных менеджеров и некоторые стратегии `official-script` имеют исполняемые адаптеры. Стратегии `official-archive`, продуктовые `manual`, сборка из исходников, VM и контейнеры отображаются в планах, но намеренно завершаются безопасной ошибкой, пока для конкретного продукта не реализованы контракты загрузки, целостности, владения, PATH и удаления.

Эта граница не позволяет широкой матрице платформ превратиться в непроверенную коллекцию команд загрузки.

## Исследование upstream

Начальная матрица поддержки обновлена **2026-08-10** на основе первичной документации upstream. См. [`research/upstream-sources.md`](research/upstream-sources.md). Версии runtime и данные EOL намеренно не считаются постоянными; манифесты содержат даты исследования и должны повторно проверяться перед изменениями, зависящими от версии.

Рекомендуемая стратегия host/domain по платформам и средам описана в [`docs/platform-strategy.md`](docs/platform-strategy.md). Поэтапный статус реализации и повышения поддержки отслеживается в [`ROADMAP.md`](ROADMAP.md).

## Документация и сообщество

- [Руководство для участников](CONTRIBUTING.md)
- [Поддержка и сообщения о проблемах](SUPPORT.md)
- [Политика безопасности](SECURITY.md)
- [Политика переводов](docs/TRANSLATIONS.md)
- [Дорожная карта](ROADMAP.md)

## Поддержать проект

Если `devkit-wulf` полезен вам, вы можете поддержать дальнейшую разработку через PayPal:

<a href="https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U" target="_blank"><img src="https://www.paypalobjects.com/en_US/DK/i/btn/btn_donateCC_LG.gif" alt="Пожертвовать через PayPal" title="PayPal - The safer, easier way to pay online!" /></a>

[Пожертвовать через PayPal](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

Отсканируйте или нажмите QR-код, чтобы открыть ту же страницу пожертвования PayPal:

[![QR-код пожертвования PayPal](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

## Лицензия

MIT — см. [`LICENSE`](LICENSE).

# devkit-wulf

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Polski](README.pl.md) | [简体中文](README.cn.md) | [Русский](README.ru.md) | [Español](README.es.md)

Безопасный, управляемый манифестами многоплатформенный bootstrapper и оркестратор сред разработки для Windows, WSL2, Linux, macOS, BSD и явно исследованных расширенных Unix-систем.

> **Статус:** pre-1.0. Комбинации платформа/среда остаются `experimental`, пока не пройдут требуемые CI-gates и проверки на целевых системах. Само наличие адаптера не означает повышения статуса поддержки.

Аудированный статус на **2026-08-11** описан в [`docs/REPOSITORY-STATUS.md`](docs/REPOSITORY-STATUS.md).

## Архитектура

`devkit-wulf` разделяет определение хоста/архитектуры, выбор источников и пакетных менеджеров, контракты сред, немутирующее планирование, проверку целостности, верификацию, состояние/владение и CI/release-gates.

Общие версионированные контракты находятся в `environments/`. Системно-нативные точки входа, предназначенные для release, находятся в `installers/`. `bin/` содержит внутренние общие ядра оркестрации на период миграции и не является универсальным межплатформенным форматом выпуска.

См. [`docs/installer-architecture.md`](docs/installer-architecture.md).

## Быстрый старт

### Нативный Linux

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

Поддерживаются Windows PowerShell 5.1 и PowerShell 7. WinGet-установки проверяют точные ID уже установленных пакетов до мутации.

### WSL2

Внутри выбранного дистрибутива WSL используйте WSL-точку входа:

```sh
./bootstrap/linux.sh
./installers/wsl/devkit-wulf.sh detect
./installers/wsl/devkit-wulf.sh plan python
```

`devkit-wulf` не создаёт WSL-дистрибутив без явного запроса и не преобразует WSL1 в WSL2 автоматически. Системные изменения WSL со стороны Windows требуют явного плана и `-AllowSystemChange`.

## Версионированные системно-нативные селекторы

Состояние аудита на **2026-08-11**:

| Селектор | Linux | WSL2 | macOS | Windows |
| --- | --- | --- | --- | --- |
| `python@3.12` | experimental-маршрут | experimental-маршрут | experimental-маршрут | experimental-маршрут |
| `go@stable` | experimental-маршрут | experimental-маршрут | experimental-маршрут | experimental-маршрут |
| `rust@stable` | experimental-маршрут | experimental-маршрут | experimental-маршрут | адаптер существует, центральный маршрут заблокирован |
| `flutter@stable` | experimental-маршрут | unsupported | experimental-маршрут | experimental-маршрут (amd64) |
| `kubectl@stable` | центрального маршрута нет | центрального маршрута нет | прямой нативный адаптер | прямой нативный адаптер |

Таблица описывает реализацию/маршрутизацию, **а не promoted support**. Windows-workflow для Go всё ещё содержит устаревшее fail-closed ожидание (issue #35). Для Windows Rust ситуация обратная: нативный адаптер существует, но центральный селектор намеренно остаётся заблокированным.

## Среды и профили

Основные среды:

`base`, `cpp`, `python`, `node`, `deno`, `bun`, `java`, `dotnet`, `go`, `rust`, `php`, `ruby`, `vscode`, `visualstudio`, `jetbrains`, `eclipse`, `android`, `flutter`, `xcode`, `docker`, `podman`, `kubectl`, `opentofu`.

Профили:

`minimal`, `web`, `backend`, `systems`, `mobile`, `devops`, `full`, `wsl-stable`, `wsl-rolling`.

**Известный drift контракта:** `profiles/profiles.json` и `tests/validate_manifests.py` всё ещё используют старый ID `apple`, тогда как канонический каталог определяет `xcode`. См. issue #34.

## Модель безопасности

Обязательные правила находятся в [`AGENTS.md`](AGENTS.md), включая:

- отсутствие скрытого fallback на неподдерживаемые комбинации;
- отсутствие автоматического `curl | sh` / `irm | iex`;
- HTTPS/source/integrity-проверки для исследованных артефактных путей;
- staging до мутации и защита от traversal/symlink/reparse-point;
- отказ от присвоения чужой или неуправляемой директории;
- отсутствие неявной постоянной мутации PATH в проверенных user-local адаптерах;
- минимально необходимые привилегии;
- fail-closed удаление без доказанного владения;
- отдельное повышение статуса поддержки только после полного набора gates.

Безопасное удаление остаётся открытым в issue #3.

## Статус CI и release

Репозиторий содержит обширные offline-fixtures Shell/PowerShell и семантические Python-валидаторы. Однако последний аудированный GitHub Actions run был заблокирован внешним состоянием аккаунта/billing **до запуска runner**. Поэтому это не считается ни зелёным CI, ни падением продуктового теста.

Сейчас нет GitHub Releases и Git tags. Release checksums/SBOM остаются открытыми в issue #6, а авторитетная валидация расширенных Unix-систем — в issue #5.

## Документация

- [Аудированный статус репозитория](docs/REPOSITORY-STATUS.md)
- [Архитектура установщиков](docs/installer-architecture.md)
- [Системно-нативные точки входа](installers/README.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)
- [Вклад в проект](CONTRIBUTING.md)
- [Поддержка](SUPPORT.md)
- [Безопасность](SECURITY.md)
- [Политика переводов](docs/TRANSLATIONS.md)

## Поддержать проект

[Пожертвовать через PayPal](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

[![QR-код пожертвования PayPal](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

## Лицензия

MIT — см. [`LICENSE`](LICENSE).

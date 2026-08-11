# devkit-wulf

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Polski](README.pl.md) | [简体中文](README.cn.md) | [Русский](README.ru.md) | [Español](README.es.md)

Bootstrapper y orquestador seguro, basado en manifiestos y multiplataforma para entornos de desarrollo en Windows, WSL2, Linux, macOS, BSD y objetivos Unix extendidos investigados explícitamente.

> **Estado:** pre-1.0. Las combinaciones plataforma/entorno permanecen como `experimental` hasta superar los gates de CI y de validación en sistemas objetivo requeridos. La mera existencia de un adaptador no implica compatibilidad promovida.

El estado auditado a **2026-08-11** se documenta en [`docs/REPOSITORY-STATUS.md`](docs/REPOSITORY-STATUS.md).

## Arquitectura

`devkit-wulf` separa detección de host/arquitectura, selección de fuentes y gestores de paquetes, contratos de entorno, planificación no mutante, integridad, verificación, estado/propiedad y gates de CI/release.

Los contratos versionados compartidos viven en `environments/`. Los puntos de entrada **orientados a release** viven en `installers/` y son nativos del sistema. `bin/` contiene los núcleos genéricos internos durante la migración y no representa un formato ejecutable universal entre sistemas operativos.

Consulta [`docs/installer-architecture.md`](docs/installer-architecture.md).

## Inicio rápido

### Linux nativo

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

Se aceptan Windows PowerShell 5.1 y PowerShell 7. Las instalaciones WinGet comprueban los IDs exactos ya instalados antes de mutar el sistema.

### WSL2

Dentro de la distribución WSL elegida utiliza el punto de entrada WSL:

```sh
./bootstrap/linux.sh
./installers/wsl/devkit-wulf.sh detect
./installers/wsl/devkit-wulf.sh plan python
```

`devkit-wulf` no crea silenciosamente una distribución WSL ni convierte WSL1 a WSL2 automáticamente. Los cambios de sistema WSL del lado de Windows requieren planificación explícita y `-AllowSystemChange`.

## Selectores versionados nativos del sistema

Estado auditado a **2026-08-11**:

| Selector | Linux | WSL2 | macOS | Windows |
| --- | --- | --- | --- | --- |
| `python@3.12` | ruta experimental | ruta experimental | ruta experimental | ruta experimental |
| `go@stable` | ruta experimental | ruta experimental | ruta experimental | ruta experimental |
| `rust@stable` | ruta experimental | ruta experimental | ruta experimental | adaptador presente, ruta central bloqueada |
| `flutter@stable` | ruta experimental | unsupported | ruta experimental | ruta experimental (amd64) |
| `kubectl@stable` | sin ruta central | sin ruta central | adaptador nativo directo | adaptador nativo directo |

Esta tabla describe implementación/routing, **no soporte promovido**. El workflow de Go para Windows todavía contiene una expectativa fail-closed obsoleta (issue #35). Windows Rust presenta el estado opuesto: existe el adaptador nativo, pero el selector central sigue bloqueado deliberadamente.

## Entornos y perfiles

Entornos principales:

`base`, `cpp`, `python`, `node`, `deno`, `bun`, `java`, `dotnet`, `go`, `rust`, `php`, `ruby`, `vscode`, `visualstudio`, `jetbrains`, `eclipse`, `android`, `flutter`, `xcode`, `docker`, `podman`, `kubectl`, `opentofu`.

Perfiles:

`minimal`, `web`, `backend`, `systems`, `mobile`, `devops`, `full`, `wsl-stable`, `wsl-rolling`.

**Drift de contrato conocido:** `profiles/profiles.json` y `tests/validate_manifests.py` todavía usan el antiguo ID `apple`, mientras que el catálogo canónico define `xcode`. Consulta issue #34.

## Modelo de seguridad

Las reglas obligatorias están en [`AGENTS.md`](AGENTS.md), entre ellas:

- ningún fallback silencioso a combinaciones no compatibles;
- ninguna ejecución automática de `curl | sh` / `irm | iex`;
- comprobaciones HTTPS/fuente/integridad en rutas de artefactos revisadas;
- staging antes de mutar y defensas contra traversal/symlink/reparse-point;
- rechazo de destinos ajenos o no administrados;
- sin mutación persistente implícita de PATH en adaptadores user-local verificados;
- privilegios limitados;
- eliminación fail-closed cuando no puede demostrarse la propiedad;
- promoción de soporte separada únicamente después de superar todos los gates.

La eliminación segura sigue abierta en issue #3.

## Estado de CI y release

El repositorio contiene numerosas fixtures offline de Shell/PowerShell y validadores semánticos Python. Sin embargo, la última ejecución auditada de GitHub Actions fue bloqueada por un estado externo de cuenta/facturación **antes de iniciar un runner**. Por tanto, no constituye ni CI verde ni un fallo de prueba del producto.

Actualmente no existen GitHub Releases ni tags Git. Los checksums/SBOM de release siguen abiertos en issue #6; la validación autoritativa de Unix extendido, en issue #5.

## Documentación

- [Estado auditado del repositorio](docs/REPOSITORY-STATUS.md)
- [Arquitectura de instaladores](docs/installer-architecture.md)
- [Puntos de entrada nativos](installers/README.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)
- [Contribución](CONTRIBUTING.md)
- [Soporte](SUPPORT.md)
- [Seguridad](SECURITY.md)
- [Política de traducciones](docs/TRANSLATIONS.md)

## Apoya el proyecto

[Donar con PayPal](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

[![Código QR de donación PayPal](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

## Licencia

MIT — consulta [`LICENSE`](LICENSE).

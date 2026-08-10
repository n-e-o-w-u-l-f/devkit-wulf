# devkit-wulf

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Polski](README.pl.md) | [简体中文](README.cn.md) | [Русский](README.ru.md) | [Español](README.es.md)

Bootstrapper y orquestador seguro, basado en manifiestos y multiplataforma para entornos de desarrollo en Windows, WSL2, Linux, macOS, BSD y objetivos Unix extendidos investigados explícitamente.

> **Estado:** bootstrap pre-1.0. Las combinaciones plataforma/entorno permanecen como `experimental` hasta superar los gates de CI o de validación en el sistema objetivo requeridos. El repositorio no anuncia deliberadamente combinaciones no verificadas como compatibles.

## Diseño

`devkit-wulf` separa las responsabilidades de:

- detección del host y la arquitectura;
- selección del gestor de paquetes;
- metadatos del entorno y política de compatibilidad;
- estrategia de instalación;
- planificación sin cambios persistentes;
- mutaciones y gestión de privilegios;
- verificación;
- seguimiento de estado y conciencia de rollback;
- gates de CI y seguridad.

El estado de compatibilidad y la estrategia de ejecución se modelan de forma independiente. Por ello, una combinación puede tener `support: experimental` y utilizar al mismo tiempo `strategy: package-manager`, `winget`, `official-script`, `official-archive`, `source`, `vm`, `container`, `wsl2` o `xcode`.

## Inicio rápido

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

Los scripts de bootstrap instalan únicamente las pequeñas dependencias de parsing/herramientas que necesita el orquestador. No instalan perfiles de desarrollo.

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

El orquestador nativo acepta Windows PowerShell 5.1 y PowerShell 7. Las instalaciones basadas en WinGet se comprueban antes de modificar el sistema para evitar reinstalar deliberadamente IDs exactos de paquetes que ya existen.

### WSL2

Ejecuta la CLI de Linux dentro de la distribución WSL seleccionada. Las distribuciones WSL se detectan de forma independiente al host Windows. `devkit-wulf` nunca crea silenciosamente una distribución WSL ni convierte WSL1 a WSL2 de forma automática.

Para revisar primero un cambio de WSL del lado de Windows:

```powershell
.\bootstrap\windows.ps1 -PlanWSL2 -Distribution Debian
```

Cualquier modificación de funciones o distribuciones WSL requiere además un shell elevado y `-AllowSystemChange`.

Los proyectos usados por herramientas Linux dentro de WSL2 deberían almacenarse normalmente en el sistema de archivos Linux. Los proyectos nativos de Windows deberían permanecer del lado de Windows; las E/S entre sistemas de archivos no se consideran el diseño predeterminado.

## Comandos

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

En Windows nativo se utilizan los parámetros PowerShell equivalentes `-Experimental` y `-AcceptRemoteScript`.

`plan` no modifica el sistema. `install` rechaza combinaciones `unsupported` y exige una aceptación experimental explícita para combinaciones que todavía no han superado todos los gates de compatibilidad. Las estrategias que aún no tienen un adaptador dedicado verificado fallan de forma cerrada en lugar de adivinar un instalador.

## Entornos iniciales

### Base y lenguajes

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

### Editores e IDE

- `vscode`
- `visualstudio`
- `jetbrains`
- `eclipse`

### Mobile / SDK de plataforma

- `android`
- `flutter`
- `apple`

### Contenedores / infraestructura

- `docker`
- `podman`
- `kubectl`
- `opentofu`

## Perfiles

- `minimal`
- `web`
- `backend`
- `systems`
- `mobile`
- `devops`
- `full`
- `wsl-stable`
- `wsl-rolling`

El perfil `full` nunca activa entornos `experimental` por sí mismo. Las entradas `unsupported` y `target-only` nunca se convierten en instalaciones del host.

## Modelo de plataformas

Objetivos principales de implementación:

- Windows 11 y clientes Windows 10 mantenidos, x64/ARM64 cuando el entorno correspondiente lo admita;
- WSL2 con Debian, Ubuntu, Arch Linux, openSUSE y Kali;
- Debian/Ubuntu/Mint/Kali/Raspberry Pi OS;
- Arch/Manjaro;
- Fedora/RHEL/Rocky/Alma;
- openSUSE;
- Alpine;
- macOS Intel y Apple Silicon.

Objetivos de investigación/validación:

- FreeBSD, OpenBSD, NetBSD, DragonFly BSD;
- illumos, Oracle Solaris, AIX.

Las entradas Unix extendidas permanecen como `experimental` o `target-only` hasta su validación en sistemas objetivo autoritativos. La capacidad de compilación cruzada se modela por separado de la compatibilidad del host.

## Modelo de seguridad

La implementación sigue los gates definidos en [`AGENTS.md`](AGENTS.md). En particular:

- no hay fallback silencioso hacia combinaciones no compatibles;
- no hay ejecución automática de `curl | sh` / `irm | iex`;
- la procedencia de las fuentes se registra en los manifiestos;
- se priorizan los gestores de paquetes y las rutas oficiales de los proveedores;
- los scripts remotos deben descargarse e inspeccionarse antes de ejecutarse;
- una discrepancia de checksum/firma produce un fallo duro cuando upstream proporciona metadatos de integridad;
- la elevación de privilegios se limita a las operaciones que realmente la requieren;
- `plan` nunca modifica el host;
- se rechaza la desinstalación destructiva cuando no puede determinarse de forma segura la propiedad de los recursos;
- las exclusiones de Windows Server se evalúan independientemente de la compatibilidad del cliente Windows cuando upstream así lo exige.

## Estructura del repositorio

```text
AGENTS.md               contrato de gobernanza y gates obligatorios
bin/                    orquestadores POSIX y PowerShell
bootstrap/              scripts mínimos de bootstrap del host
manifests/              catálogo de plataformas/entornos y esquema
profiles/               selecciones de entornos componibles
research/               investigación fechada de fuentes/compatibilidad upstream
scripts/                herramientas de validación/seguridad
tests/                  pruebas de manifiestos y CLI
.github/workflows/       gates de CI
```

## Límite actual de automatización

Las estrategias basadas en gestores de paquetes y algunas estrategias `official-script` disponen de adaptadores ejecutables. Las estrategias `official-archive`, `manual` específicas de productos, compilaciones desde código fuente, VM y contenedores se representan en los planes, pero fallan deliberadamente de forma cerrada hasta que sus contratos de descarga, integridad, propiedad, PATH y desinstalación estén implementados para cada producto.

Este límite evita que una matriz amplia de plataformas se convierta en una colección no verificada de comandos de descarga.

## Investigación upstream

La matriz inicial de compatibilidad se actualizó el **2026-08-10** a partir de documentación primaria de upstream. Consulta [`research/upstream-sources.md`](research/upstream-sources.md). Las versiones de runtimes y la información EOL no se consideran permanentes; los manifiestos registran fechas de investigación y deben volver a validarse antes de cambios sensibles a versiones.

La estrategia host/dominio recomendada por plataforma y entorno se encuentra en [`docs/platform-strategy.md`](docs/platform-strategy.md). El estado por fases de implementación y promoción se sigue en [`ROADMAP.md`](ROADMAP.md).

## Documentación y comunidad

- [Guía para contribuir](CONTRIBUTING.md)
- [Guía de soporte y reporte de problemas](SUPPORT.md)
- [Política de seguridad](SECURITY.md)
- [Política de traducciones](docs/TRANSLATIONS.md)
- [Hoja de ruta](ROADMAP.md)

## Apoya el proyecto

Si `devkit-wulf` te resulta útil, puedes apoyar su desarrollo continuo mediante PayPal:

<a href="https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U" target="_blank"><img src="https://www.paypalobjects.com/en_US/DK/i/btn/btn_donateCC_LG.gif" alt="Donar con PayPal" title="PayPal - The safer, easier way to pay online!" /></a>

[Donar con PayPal](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

Escanea o haz clic en el código QR para abrir la misma página de donación de PayPal:

[![Código QR de donación PayPal](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

## Licencia

MIT — consulta [`LICENSE`](LICENSE).

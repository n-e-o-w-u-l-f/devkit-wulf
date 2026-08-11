# devkit-wulf

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Polski](README.pl.md) | [简体中文](README.cn.md) | [Русский](README.ru.md) | [Español](README.es.md)

Bootstrapper et orchestrateur sécurisé, piloté par manifestes, pour les environnements de développement multiplateformes sous Windows, WSL2, Linux, macOS, BSD et les cibles Unix étendues explicitement étudiées.

> **Statut :** pré-1.0. Les combinaisons plateforme/environnement restent `experimental` jusqu’à la réussite des gates CI et de validation sur système cible. La présence d’un adaptateur n’implique pas une prise en charge promue.

L’état audité au **11/08/2026** est documenté dans [`docs/REPOSITORY-STATUS.md`](docs/REPOSITORY-STATUS.md).

## Architecture

`devkit-wulf` sépare la détection hôte/architecture, le choix des sources et gestionnaires de paquets, les contrats d’environnement, la planification non mutante, l’intégrité, la vérification, l’état/propriété et les gates CI/release.

Les contrats versionnés partagés vivent sous `environments/`. Les points d’entrée **destinés aux releases** vivent sous `installers/` et sont natifs à leur système. Les cœurs sous `bin/` restent des orchestrateurs internes pendant la migration et ne constituent pas un format universel inter-OS.

Voir [`docs/installer-architecture.md`](docs/installer-architecture.md).

## Démarrage rapide

### Linux natif

```sh
./bootstrap/linux.sh
./installers/linux/devkit-wulf.sh detect
./installers/linux/devkit-wulf.sh list
./installers/linux/devkit-wulf.sh plan python
./installers/linux/devkit-wulf.sh install python --experimental
./installers/linux/devkit-wulf.sh verify python
./installers/linux/devkit-wulf.sh doctor
```

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

Un bootstrap réussi ne promeut pas le support d’un environnement.

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

Windows PowerShell 5.1 et PowerShell 7 sont acceptés. Les installations WinGet vérifient les paquets exacts déjà présents avant mutation.

### WSL2

Dans la distribution WSL sélectionnée :

```sh
./bootstrap/linux.sh
./installers/wsl/devkit-wulf.sh detect
./installers/wsl/devkit-wulf.sh plan python
```

`devkit-wulf` ne crée pas silencieusement une distribution WSL et ne convertit pas automatiquement WSL1 vers WSL2. Les mutations Windows de WSL demandent une planification explicite et `-AllowSystemChange`.

## Sélecteurs versionnés natifs

État audité au **11/08/2026** :

| Sélecteur | Linux | WSL2 | macOS | Windows |
| --- | --- | --- | --- | --- |
| `python@3.12` | route expérimentale | route expérimentale | route expérimentale | route expérimentale |
| `go@stable` | route expérimentale | route expérimentale | route expérimentale | route expérimentale |
| `rust@stable` | route expérimentale | route expérimentale | route expérimentale | adaptateur présent, route centrale bloquée |
| `flutter@stable` | route expérimentale | unsupported | route expérimentale | route expérimentale (amd64) |
| `kubectl@stable` | pas de route centrale | pas de route centrale | adaptateur natif direct | adaptateur natif direct |

Cette matrice décrit l’implémentation/routage, **pas un support promu**. Le workflow Go Windows contient encore une attente fail-closed obsolète (issue #35). À l’inverse, Windows Rust possède un adaptateur natif mais reste volontairement bloqué au niveau du sélecteur central.

## Environnements et profils

Environnements principaux :

`base`, `cpp`, `python`, `node`, `deno`, `bun`, `java`, `dotnet`, `go`, `rust`, `php`, `ruby`, `vscode`, `visualstudio`, `jetbrains`, `eclipse`, `android`, `flutter`, `xcode`, `docker`, `podman`, `kubectl`, `opentofu`.

Profils :

`minimal`, `web`, `backend`, `systems`, `mobile`, `devops`, `full`, `wsl-stable`, `wsl-rolling`.

**Dérive connue :** `profiles/profiles.json` et `tests/validate_manifests.py` utilisent encore l’ancien identifiant `apple`, alors que le catalogue canonique définit `xcode`. Voir issue #34.

## Modèle de sécurité

Les règles obligatoires sont dans [`AGENTS.md`](AGENTS.md), notamment :

- aucun fallback silencieux vers une combinaison non prise en charge ;
- aucune exécution automatique de `curl | sh` / `irm | iex` ;
- validation HTTPS/source/intégrité sur les chemins d’artefacts examinés ;
- staging avant mutation et défense contre traversal/symlink/reparse-point ;
- refus d’adopter une destination étrangère/non gérée ;
- aucune mutation persistante implicite de PATH dans les adaptateurs user-local vérifiés ;
- privilèges limités ;
- désinstallation fail-closed si la propriété n’est pas prouvée ;
- promotion de support séparée après tous les gates.

La suppression sûre reste ouverte via l’issue #3.

## État CI et release

La matrice de tests contient des fixtures offline Shell/PowerShell et des validateurs sémantiques Python. Le dernier run GitHub Actions audité a cependant été bloqué **avant le démarrage d’un runner** par un état externe de compte/facturation. Il ne constitue donc ni un CI vert ni un échec de test produit.

Il n’existe actuellement ni GitHub Release ni tag Git. Les checksums/SBOM de release restent ouverts via l’issue #6, et la validation Unix étendue via l’issue #5.

## Documentation

- [État audité du dépôt](docs/REPOSITORY-STATUS.md)
- [Architecture des installateurs](docs/installer-architecture.md)
- [Points d’entrée système](installers/README.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)
- [Contribution](CONTRIBUTING.md)
- [Support](SUPPORT.md)
- [Sécurité](SECURITY.md)
- [Politique de traduction](docs/TRANSLATIONS.md)

## Soutenir le projet

[Faire un don avec PayPal](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

[![QR code de don PayPal](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

## Licence

MIT — voir [`LICENSE`](LICENSE).

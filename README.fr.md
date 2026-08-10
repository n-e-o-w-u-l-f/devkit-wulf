# devkit-wulf

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Polski](README.pl.md) | [简体中文](README.cn.md) | [Русский](README.ru.md) | [Español](README.es.md)

Bootstrapper et orchestrateur sécurisé, piloté par manifestes, pour les environnements de développement multiplateformes sous Windows, WSL2, Linux, macOS, BSD ainsi que sur des cibles Unix étendues explicitement étudiées.

> **Statut :** bootstrap pré-1.0. Les combinaisons plateforme/environnement restent `experimental` jusqu’à la réussite des gates CI ou de validation sur système cible requis. Le dépôt n’annonce volontairement aucune combinaison non vérifiée comme prise en charge.

## Conception

`devkit-wulf` sépare les responsabilités suivantes :

- détection de l’hôte et de l’architecture ;
- sélection du gestionnaire de paquets ;
- métadonnées d’environnement et politique de support ;
- stratégie d’installation ;
- planification sans modification ;
- mutation et gestion des privilèges ;
- vérification ;
- suivi d’état et prise en compte du rollback ;
- gates CI et sécurité.

Le statut de support et la stratégie d’exécution sont modélisés séparément. Une combinaison peut donc avoir `support: experimental` tout en utilisant `strategy: package-manager`, `winget`, `official-script`, `official-archive`, `source`, `vm`, `container`, `wsl2` ou `xcode`.

## Démarrage rapide

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

Les scripts de bootstrap n’installent que les petits prérequis de parsing/outillage nécessaires à l’orchestrateur. Ils n’installent pas les profils de développement.

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

L’orchestrateur natif accepte Windows PowerShell 5.1 et PowerShell 7. Les installations basées sur WinGet sont vérifiées avant toute modification afin d’éviter de réinstaller volontairement les ID de paquets exacts déjà présents.

### WSL2

Exécutez la CLI Linux dans la distribution WSL sélectionnée. Les distributions WSL sont détectées indépendamment de l’hôte Windows. `devkit-wulf` ne crée jamais silencieusement une distribution WSL et ne convertit pas automatiquement WSL1 vers WSL2.

Pour examiner d’abord une modification WSL côté Windows :

```powershell
.\bootstrap\windows.ps1 -PlanWSL2 -Distribution Debian
```

Toute modification des fonctionnalités ou distributions WSL nécessite également un shell élevé et `-AllowSystemChange`.

Les projets utilisés par des outils Linux devraient normalement être stockés dans le système de fichiers Linux de WSL2. Les projets Windows natifs devraient rester côté Windows ; les E/S inter-systèmes de fichiers ne sont volontairement pas considérées comme disposition par défaut.

## Commandes

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

Sous Windows natif, utilisez les paramètres PowerShell équivalents `-Experimental` et `-AcceptRemoteScript`.

`plan` n’effectue aucune mutation. `install` refuse les combinaisons `unsupported` et exige une acceptation expérimentale explicite pour celles qui n’ont pas encore validé tous les gates de support. Les stratégies sans adaptateur dédié vérifié échouent de façon fermée au lieu de deviner un installateur.

## Environnements initiaux

### Base et langages

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

### Éditeurs et IDE

- `vscode`
- `visualstudio`
- `jetbrains`
- `eclipse`

### Mobile / SDK de plateforme

- `android`
- `flutter`
- `apple`

### Conteneurs / infrastructure

- `docker`
- `podman`
- `kubectl`
- `opentofu`

## Profils

- `minimal`
- `web`
- `backend`
- `systems`
- `mobile`
- `devops`
- `full`
- `wsl-stable`
- `wsl-rolling`

Le profil `full` n’active jamais les environnements `experimental` de lui-même. Les entrées `unsupported` et `target-only` ne sont jamais transformées en installations hôte.

## Modèle de plateforme

Cibles principales d’implémentation :

- Windows 11 et clients Windows 10 maintenus, x64/ARM64 lorsque l’environnement concerné le permet ;
- WSL2 avec Debian, Ubuntu, Arch Linux, openSUSE et Kali ;
- Debian/Ubuntu/Mint/Kali/Raspberry Pi OS ;
- Arch/Manjaro ;
- Fedora/RHEL/Rocky/Alma ;
- openSUSE ;
- Alpine ;
- macOS Intel et Apple Silicon.

Cibles de recherche/validation :

- FreeBSD, OpenBSD, NetBSD, DragonFly BSD ;
- illumos, Oracle Solaris, AIX.

Les entrées Unix étendues restent `experimental` ou `target-only` jusqu’à validation sur des systèmes cibles faisant autorité. Les capacités de cross-compilation sont modélisées séparément du support hôte.

## Modèle de sécurité

L’implémentation suit les gates définis dans [`AGENTS.md`](AGENTS.md). En particulier :

- aucun fallback silencieux vers une combinaison non prise en charge ;
- aucune exécution automatique de `curl | sh` / `irm | iex` ;
- la provenance des sources est enregistrée dans les manifestes ;
- les gestionnaires de paquets et chemins officiels des fournisseurs sont privilégiés ;
- les scripts distants doivent être téléchargés et inspectés avant exécution ;
- les écarts de checksum/signature provoquent un échec dur lorsque l’amont fournit des métadonnées d’intégrité ;
- l’élévation de privilèges est limitée aux opérations qui l’exigent ;
- `plan` ne modifie jamais l’hôte ;
- la désinstallation destructive est refusée lorsque la propriété des ressources ne peut pas être établie de manière sûre ;
- les exclusions Windows Server sont évaluées séparément du support Windows client lorsque l’amont l’exige.

## Structure du dépôt

```text
AGENTS.md               contrat de gouvernance et gates obligatoires
bin/                    orchestrateurs POSIX et PowerShell
bootstrap/              scripts minimaux de bootstrap hôte
manifests/              catalogue plateforme/environnement et schéma
profiles/               sélections d’environnements composables
research/               recherche amont datée sur le support et les sources
scripts/                outils de validation/sécurité
tests/                  tests de manifestes et de CLI
.github/workflows/       gates CI
```

## Limite actuelle de l’automatisation

Les stratégies de gestionnaire de paquets et certaines stratégies `official-script` disposent d’adaptateurs exécutables. Les stratégies `official-archive`, `manual` spécifiques aux produits, les builds source, VM et conteneurs sont représentés dans les plans, mais échouent volontairement de façon fermée jusqu’à ce que leurs contrats de téléchargement, intégrité, propriété, PATH et désinstallation soient implémentés par produit.

Cette limite évite qu’une large matrice de plateformes ne devienne une collection non vérifiée de commandes de téléchargement.

## Recherche amont

La matrice de support initiale a été actualisée le **10/08/2026** à partir de documentation primaire des projets en amont. Voir [`research/upstream-sources.md`](research/upstream-sources.md). Les versions de runtimes et informations EOL ne sont volontairement pas considérées comme permanentes ; les manifestes enregistrent les dates de recherche et doivent être revalidés avant toute modification sensible aux versions.

Pour la stratégie recommandée hôte/domaine par plateforme et environnement, voir [`docs/platform-strategy.md`](docs/platform-strategy.md). L’état d’implémentation et de promotion par phases est suivi dans [`ROADMAP.md`](ROADMAP.md).

## Documentation et communauté

- [Guide de contribution](CONTRIBUTING.md)
- [Guide de support et de signalement](SUPPORT.md)
- [Politique de sécurité](SECURITY.md)
- [Politique de traduction](docs/TRANSLATIONS.md)
- [Feuille de route](ROADMAP.md)

## Soutenir le projet

Si `devkit-wulf` vous est utile, vous pouvez soutenir son développement continu via PayPal :

<a href="https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U" target="_blank"><img src="https://www.paypalobjects.com/en_US/DK/i/btn/btn_donateCC_LG.gif" alt="Faire un don avec PayPal" title="PayPal - The safer, easier way to pay online!" /></a>

[Faire un don avec PayPal](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

Scannez ou cliquez sur le QR code pour ouvrir la même page de don PayPal :

[![QR code de don PayPal](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

## Licence

MIT — voir [`LICENSE`](LICENSE).

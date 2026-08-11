# README Translations

`README.md` is the canonical English README for `devkit-wulf`.

The repository maintains these synchronized README variants:

- [English](../README.md)
- [Deutsch](../README.de.md)
- [Français](../README.fr.md)
- [Polski](../README.pl.md)
- [简体中文](../README.cn.md)
- [Русский](../README.ru.md)
- [Español](../README.es.md)

Synchronization baseline: **2026-08-11**.

## Translation policy

Translations must preserve technical meaning rather than follow literal word-for-word phrasing.

The following elements must remain technically consistent with the English source:

- release-facing entrypoint paths (`installers/` versus internal `bin/` cores);
- CLI commands;
- flags and PowerShell parameters;
- file and directory paths;
- environment IDs;
- profile IDs;
- versioned selectors;
- manifest keys;
- support states such as `experimental`, `unsupported` and `target-only`;
- installation strategy identifiers;
- security-gate identifiers;
- CI/release limitations;
- URLs and upstream references.

Do not translate command names, package IDs, selector IDs, manifest keys or executable names.

## Update workflow

When `README.md` changes materially:

1. update the canonical English text first;
2. identify sections whose technical meaning changed;
3. propagate those changes to every maintained translation;
4. verify that language-switcher links still point to existing files;
5. verify that release-facing paths and selector matrices still match the English source;
6. verify that environment/profile IDs match the machine-readable catalogs;
7. verify that donation, support, security and contributing links remain consistent;
8. keep code blocks equivalent unless a platform-specific example explicitly requires a difference;
9. update the synchronization baseline only after every maintained translation is reconciled.

## Translation status

All maintained README translations on the 2026-08-11 ReadmeGPT reconciliation branch describe the same pre-1.0 feature, routing and support boundary as the canonical English README.

A translated README must never:

- advertise broader support than `README.md`, the manifests or the governance gates;
- describe an adapter as centrally routed when the release entrypoint still blocks it;
- treat a direct component adapter as a promoted shared selector;
- present a blocked/never-started CI job as either passing or failing product validation;
- silently retain an obsolete environment ID or public entrypoint path after the canonical README changes.

## Adding another language

A new README translation should:

- use `README.<language-code>.md` naming;
- include the shared language switcher near the top;
- link back to the canonical English README;
- preserve all technical identifiers;
- include the same support/security caveats;
- include the project support/donation section;
- be added to this file and to the language switcher in all maintained READMEs.

## Corrections

Translation corrections are welcome through pull requests. See [`CONTRIBUTING.md`](../CONTRIBUTING.md).

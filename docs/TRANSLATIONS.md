# README Translations

`README.md` is the canonical English README for `devkit-wulf`.

The repository currently maintains these translations:

- [English](../README.md)
- [Deutsch](../README.de.md)
- [Français](../README.fr.md)
- [Polski](../README.pl.md)
- [简体中文](../README.cn.md)
- [Русский](../README.ru.md)
- [Español](../README.es.md)

## Translation policy

Translations should preserve technical meaning rather than follow literal word-for-word phrasing.

The following elements must remain technically consistent with the English source:

- CLI commands;
- flags and PowerShell parameters;
- file and directory paths;
- environment IDs;
- profile IDs;
- manifest keys;
- support states such as `experimental`, `unsupported` and `target-only`;
- installation strategy identifiers;
- security-gate identifiers;
- URLs and upstream references.

Do not translate command names, package IDs, manifest keys or executable names.

## Update workflow

When `README.md` changes materially:

1. update the canonical English text first;
2. identify sections whose technical meaning changed;
3. propagate those changes to every maintained translation;
4. verify that language-switcher links still point to existing files;
5. verify that donation, support, security and contributing links remain consistent;
6. keep code blocks equivalent unless a platform-specific example explicitly requires a difference.

## Translation status

All maintained README translations are intended to describe the same pre-1.0 feature and support boundary.

A translated README must not advertise broader support than `README.md` or the manifests.

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
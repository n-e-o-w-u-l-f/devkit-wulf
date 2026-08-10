# Security Policy

## Scope

`devkit-wulf` installs developer tooling and may invoke package managers with elevated privileges. Treat installer, manifest, checksum, repository-key and CI changes as security-sensitive.

## Reporting

Do not publish credentials, private keys, access tokens, machine identifiers or exploit details in public issues. Use GitHub's private vulnerability reporting feature when enabled for this repository, or contact the repository owner through an established private channel.

## Security invariants

- HTTPS is required for downloaded executable content.
- Official OS repositories and official vendor sources are preferred.
- Integrity/signature metadata is verified when upstream provides it.
- Verification bypasses are not automatic fallbacks.
- Remote scripts are downloaded before execution; direct pipe-to-shell execution is not an approved default.
- Privilege escalation is limited to operations that require it.
- Unsupported platform/environment combinations fail closed.
- Existing system Python/Ruby/toolchains are not destructively replaced.
- Uninstall must not remove dependencies whose ownership cannot be established.

## Release blocking findings

A release is blocked by unresolved critical findings involving command injection, arbitrary file overwrite, unsafe recursive deletion, signature/checksum bypass, credential exposure, privilege-escalation mistakes, or supply-chain provenance ambiguity.

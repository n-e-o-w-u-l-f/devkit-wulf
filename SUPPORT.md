# Support

## Start with the documentation

Before opening an issue, review:

- [`README.md`](README.md)
- [`AGENTS.md`](AGENTS.md)
- [`ROADMAP.md`](ROADMAP.md)
- [`SECURITY.md`](SECURITY.md)
- [`docs/platform-strategy.md`](docs/platform-strategy.md)
- [`research/upstream-sources.md`](research/upstream-sources.md)

## Getting help

When reporting a problem, include enough information to reproduce the host and installation decision.

Please provide:

- host operating system;
- OS/distribution version;
- architecture;
- shell and PowerShell version where applicable;
- target environment or profile;
- native, WSL2, VM or container domain;
- exact command you ran;
- full relevant output/error;
- output of `devkit-wulf detect`;
- output of `devkit-wulf plan <environment>` where possible;
- whether the problem occurred during `plan`, `install`, `verify`, `remove` or `doctor`;
- whether the environment already existed before `devkit-wulf` was used.

Do not include passwords, access tokens, private keys or other secrets in issue output.

## Appropriate issue types

Open an issue for:

- reproducible bugs;
- host/platform detection problems;
- package-manager adapter problems;
- environment verification failures;
- documentation errors;
- support-matrix corrections backed by current official upstream documentation;
- feature requests that fit the orchestrator scope;
- accessibility or translation corrections.

## Unsupported or experimental combinations

An `unsupported`, `target-only` or `experimental` result is not automatically a bug.

If you believe the status is incorrect, include current primary upstream evidence for:

- supported host OS/version;
- architecture support;
- official installation mechanism;
- integrity/signing mechanism;
- any important limitations.

Support is not promoted solely because a package can be forced to install once.

## Security

For security-sensitive reports, follow [`SECURITY.md`](SECURITY.md) instead of publishing exploit details in a normal issue.

## GitHub Actions status

A failed workflow can also be caused by repository/account infrastructure rather than the code itself. Check the job annotation and logs before treating a non-started job as a test failure.

## Support the project

If `devkit-wulf` is useful to you, you can support ongoing development through PayPal:

[![Donate with PayPal](https://www.paypalobjects.com/en_US/DK/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

[Donate via PayPal](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

[![PayPal donation QR code](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)
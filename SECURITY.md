# Security Policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Use GitHub's
private vulnerability reporting instead:

**[Report a vulnerability](https://github.com/Kumo-Craft/terraform-azurerm-landing-zone/security/advisories/new)**

The report opens a private advisory visible only to the maintainers. You
can expect an acknowledgement within a few days, and credit in the
advisory once a fix ships (unless you prefer to stay anonymous).

## Supported versions

Only the **latest release** (highest `v*` tag) is supported. Fixes ship
as new releases — old tags are immutable and never patched in place.

## Scope

In scope: the Terraform modules in this repository (insecure defaults,
privilege-escalation paths, secrets handling) and the CI/CD workflows
under `.github/workflows/`.

Out of scope: vulnerabilities in upstream Terraform providers
(`azurerm`, `azapi`, …) or in third-party GitHub Actions this repo
consumes — please report those to their own maintainers.

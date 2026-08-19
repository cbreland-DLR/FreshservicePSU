# FreshservicePSU

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

FreshservicePSU is a PowerShell module for the standard Freshservice REST API
v2. This repository is a community-maintained fork of
[flycastpartnersinc/FreshservicePS](https://github.com/flycastpartnersinc/FreshservicePS)
and is not an official Freshworks product.

## Status

The repository is in the transition stage of a breaking, PowerShell 7.6 and
PowerShell Universal modernization. The inherited command surface has been
removed. The checked-in module exports the accepted 23-command surface
and includes Phase 7 consumer examples under [examples/](examples/).
It is not yet a packaged `1.0.0` release. Backward compatibility with
the legacy module is not a goal. Do not use the development branch for
critical automation.

The evidence-collection tooling needed for the remaining PSU and
Freshservice sandbox questions is complete and tested. Operators still
need to run the matrices in [tools/README.md](tools/README.md) before
identity and two optional commands are declared deployment-ready.

For where the work stands and what happens next, see
[Where the work stands](CLAUDE.md#where-the-work-stands) in `CLAUDE.md`.

This fork will not publish the redesign to the PowerShell Gallery. Versioned,
checksummed module archives will be attached to this repository's GitHub
releases for PSU deployment. The similarly named `FreshservicePS` Gallery
package contains the upstream project, not the code in this repository.

## What FreshservicePSU will be

FreshservicePSU will be a small, PSU-first PowerShell module for building
Freshservice pages, APIs, reports, schedules, and automations. Its completed
public surface will contain 23 commands organized around:

- ticket creation, updates, notes, reads, searches, fields, and activity;
- agent, group, department, location, and requester reference data;
- asset lookup, controlled asset updates, soft delete, asset types, and assignment history;
- requested-item and task reporting;
- ticket and cross-ticket approval reporting; and
- SLA-policy and business-hours configuration reporting.

Every command will use a shared request pipeline with bounded paging and
records, validation, typed output, safe retries, tenant-aware rate limiting,
normalized errors, and secret-safe auditing. PSU supplies trusted identity,
environment, and secret-provider context. PSU controls who may run the calling
app, API, or script. Interactive writes use the selected personal credential;
schedules and automations use a named system identity.

The PSU identity adapter supports both SAML and OpenID Connect. SAML is the
current deployment, but provider-specific claims are normalized into the same
immutable principal ID and readable username so a later OIDC migration does not
change command behavior or credential mappings.

FreshservicePSU is a command library used by other scripts; it is not a
reporting database or application data store. Consuming scripts and apps own
their schedules, checkpoints, persistence, refresh cadence, retention, and
data-access policy. Access control belongs to the consuming PSU app, API, or
script and to the permissions of the resolved Freshservice API key; the module
does not define or enforce its own PSU roles.

The module will intentionally favor the PSU workloads above over broad API
coverage. It will not preserve legacy connection profiles or commands, provide
external asset synchronization, or expose asset create, restore,
permanent delete, or move. Soft delete is `Remove-FreshServiceAsset`. The
authoritative command-by-command behavior is in the
[supported command reference](docs/SUPPORTED_COMMANDS.md).

## Product boundaries

- Standard Freshservice, not Freshservice for MSPs
- Freshservice API v2 only
- Enterprise-plan features are allowed, subject to tenant feature flags
- PowerShell Universal is the primary runtime for new work

## Current development checkout

This project now lives absorbed inside the UniversalAutomation PSU instance
repository, at `Repository/Modules/FreshservicePSU/` (versioned module code
under `0.1.6/`, with this project's own docs/tests/tools/build alongside it).
For standalone documentation review of the upstream fork, clone it directly:

```powershell
git clone https://github.com/cbreland-DLR/FreshservicePSU.git
Set-Location ./FreshservicePSU
```

The inherited legacy runtime, command set, help, and live-tenant tests have
been removed from the tree; see `docs/COMMAND_PRUNE_LIST.md` for the record of
what was removed and why.

## Documentation

- [Target architecture](docs/ARCHITECTURE.md)
- [Supported command reference](docs/SUPPORTED_COMMANDS.md)
- [Command prune decision](docs/COMMAND_PRUNE_LIST.md)
- [Open questions](docs/OPEN_QUESTIONS.md)
- [PowerShell Universal setup](docs/PSU_SETUP.md)
- [Freshservice API v2 coverage](docs/API_V2_COVERAGE_MATRIX.md)
- [Consumer examples](examples/README.md)
- [Security policy](SECURITY.md)

## Testing

The default validation gate is offline and includes unit, contract,
architecture, documentation, analyzer, manifest, and clean-import checks.
Operator evidence tools have a separate mocked offline gate:

```powershell
./build.ps1 -Task Validate,Tools
```

Credentialed PSU and Freshservice evidence runs remain explicit and opt-in.
The Freshservice note-authorship probe creates notes and must be used only with
the documented acknowledgement on disposable sandbox tickets; never run it
against production.

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) before submitting a change.

## Support and issues

Report reproducible bugs and proposed changes in this fork's
[issue tracker](https://github.com/cbreland-DLR/FreshservicePSU/issues). For API
behavior and limits, consult the
[Freshservice API v2 documentation](https://api.freshservice.com/).

## Attribution and license

FreshservicePSU is derived from FreshservicePS, originally developed by Rob
Simmers and Flycast Partners, Inc. This fork retains the original Git history
and copyright notice.

The project is distributed under the [MIT License](LICENSE). Freshservice and
Freshworks are trademarks of their respective owner. Use of those names does
not imply endorsement of this fork.

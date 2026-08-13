# FreshservicePSU

PowerShell module wrapping the Freshservice REST API.

## Scope constraints

These are fixed for this project. Do not add coverage, tests, or documentation outside them, and do not propose designs that assume otherwise.

- **Standard Freshservice only — not Freshservice for MSPs.** MSP-specific endpoints, objects, and multi-customer constructs are out of scope. Endpoint coverage reviews are scoped the same way (see `docs/API_V2_COVERAGE_MATRIX.md`).
- **Freshservice API v2 only.** Earlier API versions are out of scope and are not a source of evidence about v2 behavior. Confirm behavior against the v2 reference or against a live tenant.
- **Enterprise plan.** Features gated to Enterprise may be used. Availability still varies by tenant feature flags, so verify against the target tenant before implementing.
- **Single workspace.** The tenant has one workspace. Do not add workspace-move commands, workspace CRUD, or `workspace_id` parameters on public commands, and do not design for workspace selection in configuration or the execution context. A value that can only ever be one value is not a parameter.
- **Releases, problems, and changes are outside the committed command surface.** Do not implement their resource families or offer them as parent types on notes, tasks, time entries, or restore without a new accepted workload decision.
- **Asset support is focused.** The committed asset surface is `Get-FreshServiceAsset`, `Set-FreshServiceAsset`, `Get-FreshServiceAssetType`, and `Get-FreshServiceAssetAssignmentHistory`. Components, relationships, contracts, purchase orders, products, vendors, software, physical subtypes, devices, cloud resources, cloud relationships, cloud details, and lifecycle events remain out of scope.
- **Features the tenant does not use are out of scope.** Time entries, attachments, journeys, and employee onboarding and offboarding. Onboarding commands exist today (`Get`/`New-FreshServiceOnboardingRequest`) and are removed rather than migrated, because the tenant has not implemented the feature.

## Intended workloads

The near-term PSU need is narrow. Design and prioritize against it; see `docs/ARCHITECTURE.md` §1.

1. Create a ticket.
2. Add a note to a ticket.
3. Close a ticket — a separate command from the note, composed in a script rather than merged into one command.
4. Read tickets, approvals, fulfillment data, policies, people, and assets for PSU pages, reports, and scheduled extracts.
5. Read and update ordinary asset properties from authorized PSU apps and automations.

The authoritative 22-command inventory is `docs/SUPPORTED_COMMANDS.md`. CSAT is conditional, time entries are excluded, and external asset synchronization is not a project workload.

Everything outside that inventory is uncommitted. Do not treat an existing legacy command as evidence that its family is in scope.

## Deployment target

PowerShell Universal is the primary runtime for new work. See `docs/ARCHITECTURE_MODERNIZATION_PLAN.md` for the document map and authority order, `docs/ARCHITECTURE.md` for the redesign, and `docs/CURRENT_STATE_REVIEW.md` for the legacy findings.

**Backward compatibility is not a constraint.** Converting the module for PSU may change any feature, for any part of the surface — command names and parameters, authentication, the connection model, output shapes, module loading, aliases. Existing scripts, saved profiles, and PowerShell Gallery consumers do not have to keep working.

This applies to the whole conversion, not to a list of exceptions. Do not preserve an existing behavior, keep a shim, or add a compatibility parameter just because something might depend on it, and do not weaken a design to avoid a break. Prefer the design that is right for PSU and record the break.

Two things this does not mean:

- The break still gets **documented**. Name what changed so the migration is a known cost rather than a surprise.
- Repository history is sufficient for legacy reference. Do not maintain a compatibility branch or parallel legacy implementation as part of this project.

## Repository layout

- `FreshservicePSU/Public/<Resource>/` — one file per public command, grouped by API resource.
- `FreshservicePSU/Private/` — shared target internals; all HTTP goes through the new request pipeline.
- `FreshservicePSU/FreshservicePSU.psd1` — explicit exports, validated against the accepted inventory.
- `tests/` — offline unit and contract tests by default; credentialed PSU and live tests are separate.
- `docs/en-US/` — generated help for supported commands only.
- `docs/PSU_SETUP.md` — operator installation, configuration, identity, validation, upgrade, and rollback guide.
- `SECURITY.md` — private vulnerability reporting and secret-handling policy.

## Conventions

- Command names use `FreshService`; the target module exports no generated aliases.
- Public commands use focused PowerShell parameters and one operation/resource shape per command. Shared internals perform transport and serialization.

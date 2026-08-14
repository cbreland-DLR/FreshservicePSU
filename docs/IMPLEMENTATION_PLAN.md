# FreshservicePSU implementation plan

- **Status:** Accepted sequence
- **Date:** 2026-08-12
- **Architecture:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Command reference:** [SUPPORTED_COMMANDS.md](SUPPORTED_COMMANDS.md)
- **Open questions:** [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md)
- **Evidence:** [CURRENT_STATE_REVIEW.md](CURRENT_STATE_REVIEW.md)
- **Release:** Breaking major version; backward compatibility is not a goal

## 1. Execution rules

- The architecture owns design decisions and security invariants.
- The supported-command reference owns the public command inventory.
- This plan owns sequencing, deliverables, dependencies, and exit criteria.
- A phase is complete only when its tests and repository checks pass.
- Build the new major from a clean PowerShell 7.6 module skeleton. Do not mechanically modernize legacy commands that will be removed.
- Do not maintain, release, tag, or branch a parallel legacy implementation as part of this project.
- Remove legacy connection, transport, import-state, command, help, and test code early so it cannot become an accidental dependency.
- New endpoints use the shared request pipeline from their first implementation.
- Unit and contract tests are the default CI path. PSU and live Freshservice tests run separately in credentialed environments.
- Documentation and endpoint decisions change in the same commit as the command or contract they describe.

## 2. Supported command set

The completed module exports these 22 commands and no generated aliases:

| Area | Command | Purpose |
| --- | --- | --- |
| Tickets | `New-FreshServiceTicket` | Create a ticket |
| Tickets | `Set-FreshServiceTicket` | Update or close a ticket |
| Tickets | `Get-FreshServiceTicket` | Read one ticket or a bounded list |
| Tickets | `Search-FreshServiceTicket` | Filter tickets for reports and apps |
| Tickets | `Add-FreshServiceTicketNote` | Add a private or public note |
| Tickets | `Get-FreshServiceTicketField` | Build dynamic ticket forms and resolve values |
| Tickets | `Get-FreshServiceTicketActivity` | Display and extract ticket activity history |
| Reference data | `Get-FreshServiceAgentGroup` | Assignment choices and report dimensions |
| Reference data | `Get-FreshServiceDepartment` | Form choices and report dimensions |
| Reference data | `Get-FreshServiceLocation` | Form choices and report dimensions |
| Reference data | `Get-FreshServiceAgent` | Assignee choices and report dimensions |
| Reference data | `Get-FreshServiceRequester` | Requester lookup and reporting |
| Assets | `Get-FreshServiceAsset` | Asset lookup, apps, and reporting |
| Assets | `Set-FreshServiceAsset` | Controlled asset updates from PSU apps and automations |
| Assets | `Get-FreshServiceAssetType` | Asset-type lookup and validation |
| Assets | `Get-FreshServiceAssetAssignmentHistory` | Asset assignment audit and reporting |
| Fulfillment | `Get-FreshServiceRequestedItem` | Catalog demand and fulfillment reports |
| Fulfillment | `Get-FreshServiceTask` | Ticket-task backlog and duration reports |
| Approvals | `Get-FreshServiceRequestApproval` | Read approvals belonging to a ticket |
| Approvals | `Search-FreshServiceApproval` | Retrieve filtered approvals across tickets |
| Policy | `Get-FreshServiceSLAPolicy` | SLA configuration reports |
| Policy | `Get-FreshServiceBusinessHour` | Business-hours configuration reports |

CSAT remains conditional and is not part of the committed surface. Time entries remain out of scope. Asset commands are general PSU capabilities for authorized pages, reports, schedules, and automations; no external synchronization workflow is part of this project.

## 3. Phase overview

| Phase | Outcome | Depends on |
| --- | --- | --- |
| 0 | Scope and documentation agree on the completed product | None |
| 1 | PSU identity, deployment, tenant behavior, and operational limits are proven | 0 |
| 2 | A clean PowerShell 7.6 module and offline CI foundation replace the legacy implementation | 0 |
| 3 | Security, configuration, execution-context, response, error, and audit contracts exist | 2 plus current-SAML answers to Q1-Q2 |
| 4 | The shared request, pagination, cache, retry, and rate-limit pipeline is complete | 3 plus Phase 1 single-node limiter-provider evidence |
| 5 | All read-only commands are complete in dependency order | 4; Q8-Q9 gate only their affected reads and Q13 is answered per command |
| 6 | Ticket and asset mutation commands are complete | Required Phase 5 dependencies; Q7 gates only note authorship |
| 7 | Example consumer scripts and PSU integration tests validate the command surface | 6 |
| 8 | Module packaging, documentation, CI, and the breaking release are complete | 7 plus Q3 runtime evidence |

Phases 1 and 2 may proceed in parallel after Phase 0. Phase 3 may begin when the
current SAML portions of Q1 and Q2 and the Phase 2 foundation are complete; it
does not wait for planned-OIDC evidence, unrelated endpoint checks, or final
runtime-matrix evidence.

### Open-question gates

| Questions | Gate | Work that remains available |
| --- | --- | --- |
| Q1-Q2 | Completion of the Phase 3 identity adapter and personal-secret mapping for current SAML. OIDC evidence gates only OIDC deployment readiness. | Phase 2 and identity-independent private contracts and tests. |
| Q3 | Phase 8 compatibility matrix and final release validation. | All implementation on the declared PSU 2026.x and PowerShell 7.6 targets. |
| Q7 | Note-authorship completion in Phase 6 and final simplification or retention of personal keys. | Every other command and the default personal-key design. |
| Q8 | `Search-FreshServiceApproval` only. | The other 21 provisional commands. |
| Q9 | `Get-FreshServiceAssetAssignmentHistory` only. | The other 21 provisional commands. |
| Q13 | Final typed output for each command as that command is completed. | Starting and implementing each slice before its output table is finalized. |
| Q15 | Completion of the Phase 4 production limiter provider. | Provider interfaces, deterministic in-memory tests, and unrelated pipeline work. |

Conditional future-scope items have no phase dependency until promoted.

## 4. Phase 0 — Freeze scope and align documentation

### Deliverables

- Make `SUPPORTED_COMMANDS.md`, `COMMAND_PRUNE_LIST.md`, `ARCHITECTURE.md`, this plan, `CLAUDE.md`, and the README agree on the 22-command surface.
- Classify every endpoint-comparison CSV row as `Add`, `Skip`, or `Conditional` and record a short workload reason.
- Record the following closed decisions:
  - The tenant has one workspace; no public workspace commands or `workspace_id` parameters exist.
  - Interactive writes use the authenticated user's selected credential.
  - Schedules, background automations, and Workflow Automator calls use a named system identity.
  - PSU controls access to consuming resources and Freshservice API keys provide endpoint permissions; the module defines no PSU roles.
  - The PSU adapter normalizes SAML and OIDC into the same immutable principal ID and readable username; SAML is current and OIDC compatibility is required.
  - PSU variables supply non-secret configuration and PSU's built-in vault supplies secrets.
  - A shared stage/tenant/endpoint limiter is authoritative; PSU concurrency limits supplement it, and production never silently falls back to process-local limiter state.
  - Production uses one PSU node; the limiter combines server-level PSU cache with an OS-named cross-process mutex and does not persist state to a database.
  - Documented Enterprise limits seed the limiter; response headers update its runtime state.
  - Typed objects and properties are the compatibility contract; format views are presentation only.
  - Asset commands are available for PSU apps and automations without prescribing an external synchronization design.
  - Consuming scripts own UI, schedules, reporting persistence, checkpoints, refresh, retention, and data-access policy.
  - The module emits typed `FreshservicePSU.AuditEvent` objects on the tagged PowerShell information stream but does not own an audit sink or retention policy.
  - Version `1.0.0` replaces the inherited module GUID and is distributed as a checksummed GitHub release artifact, not through the PowerShell Gallery.
  - Time entries, releases, attachments, employee lifecycle, and CMDB extension families remain out of scope.
- Define each command's minimum public parameters and stable output properties before that command is exported. A slice may start with its Q13 output table still in progress, but it cannot meet its exit criteria until the table and contract tests are complete.
- Remove completed-product wording that contradicts the development status of the current branch.

### Exit criteria

- One script can extract the 22 expected names from `SUPPORTED_COMMANDS.md`, and every authoritative document reports the same count and names.
- No accepted document makes an external asset synchronization workflow part of the project.
- Open questions are assigned only to the localized gates in the table above; they do not block the clean skeleton or unrelated command work.
- Every endpoint-comparison row has an explicit decision.

## 5. Phase 1 — PSU identity and deployment evidence

This phase records facts from the PSU test instance and Freshservice sandbox. It does not implement production module behavior. It gathers answers for Q1-Q3, Q7-Q9, and Q15, but downstream work follows the localized gates above rather than waiting for every Phase 1 question.

### Deliverables

- Identify the trusted PSU identity values for Apps, authenticated APIs, Automation jobs, schedules, and app-token calls.
- Normalize SAML and OIDC claims into one execution-principal contract. For Entra ID, use tenant plus immutable object ID as the credential-map key and UPN as the readable identity and requester lookup value.
- Prove that the same Entra user produces the same canonical principal ID under current SAML and planned OIDC mappings.
- Prove identity behavior across reused runspaces and separate prod/dev PSU environments.
- Verify the exact PSU 2026.x release, PowerShell 7.6 patch, production operating system, built-in secret vault behavior, and the single-node limiter provider's server-level cache and OS-named mutex behavior across actual PSU worker processes.
- Measure the interactive PSU timeout and set initial retry budgets below it.
- Record the documented Enterprise overall and endpoint-specific limits and verify that representative responses expose the expected remaining-credit, current-request-cost, and `Retry-After` headers.
- Verify endpoint entitlement and response shape for asset assignment history and global approval search.
- Run the note-authorship sandbox spike with and without `user_id`. Record authorship, required privilege, and Freshservice audit behavior.
- Decide whether a correlation ID remains audit-only or is also accepted as an outbound header after a sandbox test.

### Exit criteria

- Each supported PSU surface and authentication type has a documented identity source.
- Synthetic SAML and OIDC contract tests pass even before OIDC is enabled; development-PSU OIDC integration evidence is required before OIDC is declared deployment-ready.
- Schedules and noninteractive executions are proven to use the named system identity.
- Prod and dev environment and secret-provider boundaries are recorded.
- Timeout, retry, single-node atomic limiter provider, supported-OS, correlation, and note-authorship decisions have recorded outcomes; documented Enterprise limits seed the limiter and response headers provide runtime telemetry.
- Asset assignment history and global approval search are either proven available or returned to Phase 0 for an explicit scope change. An unavailable result under Q8 or Q9 removes `Search-FreshServiceApproval` or `Get-FreshServiceAssetAssignmentHistory` from the supported set, changing the exported command count.
- Q1 through Q3, Q7 through Q9, and Q15 are answered, recorded in the architecture or this plan, and removed from `OPEN_QUESTIONS.md`.

## 6. Phase 2 — Clean PowerShell 7.6 module and CI foundation

Build the target module without carrying the legacy runtime or command loader forward.

### Deliverables

- Replace the legacy module tree with the target layout for `Public`, `Private`, tests, formats, and help.
- Set `PowerShellVersion = '7.6'` and `CompatiblePSEditions = @('Core')`.
- Remove legacy public commands, generated aliases, connection profiles, profile persistence, import state, global variables, banners, and `Invoke-FreshworksRestMethod`.
- Remove legacy help topics and live-tenant resource tests. See *Stale artifact cleanup* below for the full inventory.
- Establish an explicit manifest export list that grows only when a command meets its phase exit criteria.
- Add an expected-command inventory test against the accepted 22-command catalog, while permitting a documented implementation subset until Phase 6 completes.
- Configure PSScriptAnalyzer, formatting, `Test-ModuleManifest`, import, unit, and contract-test lanes on the supported PowerShell 7.6 operating system.
- Add the naming-boundary architecture check from `ARCHITECTURE.md` §12: `Private/` functions match `^[A-Z][a-zA-Z]*-Fsu[A-Z]` case-sensitively and never contain `FreshService`, `Public/` functions never contain `Fsu`, and `AliasesToExport`, `VariablesToExport`, and `CmdletsToExport` are empty. This must exist before Phase 4 writes the pipeline helpers.
- Add architecture checks rejecting `Desktop`, versions below 7.6, `UseBasicParsing`, `ServicePointManager`, `System.Web`, direct public-command HTTP calls, and process-global credential or context state.
- Define JSON depth, UTF-8 without BOM, date, null, enum, `SecureString`, and multipart conventions for later pipeline tests.

### Stale artifact cleanup

Removing a command is not finished when its `.ps1` file is deleted. Each removed command leaves documentation and test artifacts that keep describing a surface that no longer exists, and a stale help topic is worse than a missing one — it reads as a supported command. As of 2026-08-12 the tree carried 165 public command files and 165 generated help topics against a target of 22. Phase 2 removed all of them; the table below records the before and after state of that sweep, which is complete.

Delete in the same change as the command removal:

| Artifact | Current state | Target state |
| --- | --- | --- |
| `FreshservicePSU/Public/<Resource>/*.ps1` | 165 command files across 30+ resource folders | Only the supported commands, in folders named for the resources they serve |
| `docs/en-US/*.md` | 165 generated topics, including `Connect-Freshservice.md` and other removed commands | Exactly one topic per exported command, regenerated rather than hand-edited |
| `tests/` | Legacy live-tenant resource tests per command family | Offline lanes per §14; no test referencing a removed command |
| `FreshservicePSU.psd1` | Legacy export list and alias generation | Explicit export list matching `SUPPORTED_COMMANDS.md` |
| `README.md`, `CHANGELOG.md` | Inherited upstream examples and history describing removed commands | Fork-scoped usage against the supported surface; inherited history retained but clearly labeled as pre-fork |

`COMMAND_PRUNE_LIST.md` is the authority for which names go, and it stays after the deletion: it is the record of what was removed and why, and Phase 8's release notes are written from it. Do not delete the prune list as part of the cleanup.

### Tests and exit criteria

- The clean module imports without network, disk, secret, profile, alias, banner, or console side effects.
- Default CI requires neither PSU nor Freshservice credentials.
- Repository searches find no legacy connection, transport, compatibility, or runtime-state implementation.
- Unsupported command files and help no longer exist in the target tree.
- A documentation test asserts that the set of `docs/en-US/*.md` basenames equals the set of exported commands exactly — no orphan topic, no undocumented command. This test is added with the cleanup, since it cannot pass before it.
- No file outside `COMMAND_PRUNE_LIST.md`, `CURRENT_STATE_REVIEW.md`, and `API_V2_COVERAGE_MATRIX.md` references a removed command name.
- Manifest, import, analyzer, formatting, and architecture checks pass.

## 7. Phase 3 — Core security and execution contracts

### Implementation status

As of 2026-08-13, the identity-independent contracts have been implemented and
unit-tested: `Test-FsuConfiguration` validates the configuration contract;
`ConvertTo-FsuNormalizedError` and `New-FsuErrorRecord` handle error normalization
and construction; `New-FsuResponse` provides the response metadata envelope;
`New-FsuRetryPolicy` and `Get-FsuRetryDecision` implement retry policy with
testable, injectable-clock decision logic; and `New-FsuAuditEvent` and
`Write-FsuAuditEvent` emit audit events from a closed allowlist to the tagged
information stream. Five new unit-test files document these contracts; the
offline suite now contains 196 passing tests and 2 skipped. The identity,
credential-selection, and fail-closed PSU-adapter deliverables remain blocked on
Q1 and Q2. The phase is not complete and its exit criteria are unmet.

### Deliverables

Define immutable internal contracts for:

- `Freshservice.Configuration`
- `Freshservice.ExecutionPrincipal`
- `Freshservice.ResolvedCredential`
- `Freshservice.Context`
- `Freshservice.RetryPolicy`
- `Freshservice.Response`
- normalized Freshservice errors
- safe audit events

Implement configuration validation, the fail-closed PSU adapter, credential lookup, personal/system selection, and per-operation context creation. Resolve the context for every operation and never cache it.

Read `FreshservicePSUConfig` for every public operation and validate schema
version `1.0`, the exact allowed property set, trusted URIs and issuers, and
unique personal-secret mappings before resolving a secret. Emit audit objects as
`FreshservicePSU.AuditEvent` information records tagged
`FreshservicePSU.Audit`; audit objects never enter success output.

### Tests

- Personal mapping, permitted fallback, denied fallback, broken secret, rejected personal key, unknown interactive identity, and scheduled execution.
- Duplicate or ambiguous mappings and missing or invalid configuration fail closed.
- Prod cannot resolve dev secrets and dev cannot resolve prod secrets.
- Context, response, error, and audit objects do not format or serialize authorization material.
- Reused and concurrent runspaces cannot retain or exchange contexts or credentials.
- User-controlled parameters cannot spoof identity, authentication type, stage, tenant, or secret references.
- Unknown configuration properties, unsupported schema versions, unsafe base URIs, and duplicate or case-colliding mappings fail before secret resolution.
- Audit tests prove type/tag stability, redaction, one terminal event per attempted operation, and separation from success output.

### Exit criteria

- Credential selection is deterministic and fully unit-tested.
- Public entry without trusted PSU invocation data fails before secret resolution.
- No context or key enters module state, PSU cache, output, disk, or logs.
- Interactive and noninteractive audit attribution follows the accepted Phase 0 policy.

## 8. Phase 4 — Shared request pipeline

### Sequencing within the phase

The phase as a whole depends on Phase 3 and on Phase 1 limiter evidence, neither
of which is complete. Four deliverables do not: `New-FsuUri`,
`ConvertTo-FsuRequestBody`, `ConvertFrom-FsuResponse`, and the limiter provider
interface with its in-memory provider. They are pure functions over contracts
that already exist, they consume an injected context rather than resolving one,
and the Q15 gate reserves provider interfaces and deterministic in-memory tests
as available work. Building them early is consistent with the exit criterion
that the pipeline be usable without PSU through explicit private test contexts.

Per-request authentication, paged requests end to end, the production limiter
provider, and PSU-cache-backed reference data remain blocked.

### Deliverables

Implement:

- `Invoke-FsuRequest`
- `Invoke-FsuPagedRequest`
- `New-FsuUri`
- `ConvertTo-FsuRequestBody`
- `ConvertFrom-FsuResponse`

`New-FsuErrorRecord` was listed here originally but landed in Phase 3, where the
normalized-error contract needed it; Phase 4 consumes it rather than building it.

Add per-request authentication, safe logging, connection reuse, URI and query encoding, JSON and multipart serialization, explicit response extraction, typed output support, bounded retry policies, uncertain-outcome errors, page streaming, partial-result errors, cancellation, record caps, page-500 enforcement, token pagination, API-version checks, rate telemetry, the shared limiter, and reference-data caching.

Use PSU cache for eligible ticket-field, asset-type, agent, group, department, and location reference data. Keys include stage, tenant, resource, and query; the default TTL is 15 minutes. Provide a private/admin invalidation mechanism and a per-call cache bypass without adding a business command to the public export surface.

Implement the limiter behind an atomic provider contract. The in-memory provider
is test-only. The production provider uses non-persistent server-level PSU cache
inside an OS-named mutex proven across the single node's worker processes and
never degrades silently to uncoordinated process-local state. Define fail-closed
provider behavior and test competing reservations across runspaces and
processes. Multi-node support is out of scope.

### Contract tests

- Exact method, URI, escaped path, query, headers, JSON, multipart body, response property, and `PSTypeName`.
- Spaces, Unicode, reserved characters, arrays, dates, nulls, and conditional embedded resources.
- `Retry-After` in seconds and HTTP-date form.
- Idempotent replay, non-idempotent refusal, jitter bounds, attempt cap, and total-time cap.
- `429`, ambiguous timeout, credential errors, common `4xx`, feature-gated `403`, conflict, media-type, and `5xx` behavior.
- Interactive requests never wait beyond their budget; background waits remain bounded.
- Link and token pagination, maximum `per_page`, page-501 refusal, streaming, and record caps.
- Actual request cost comes from `X-RateLimit-Used-CurrentRequest`.
- Cache hits, stage/tenant isolation, TTL expiry, invalidation, and bypass.
- A later-page failure reports pages completed and records emitted without exposing continuation tokens or response bodies; examples treat the entire run as incomplete.
- Cancellation before send, during response, between pages, and during retry wait performs no retry and disposes request resources.
- Atomic limiter contention, stale-window expiry, provider unavailability, recovery, and process/runspace isolation.
- Logs, errors, and audit events contain no credentials, authorization values, response bodies, or sensitive query values.

### Exit criteria

- The pipeline is usable without PSU through explicit private test contexts.
- Retry, rate-limit, cache, and pagination decisions are deterministic under fake clock and random sources.
- Mutations never report fabricated success or silently return `$null` for an operation that did not occur.
- The pipeline has no process-global side effects.
- No production path uses a process-local limiter when the shared provider is unavailable.

## 9. Phase 5 — Read-only commands

Implement reads as vertical slices. Each command includes code, help, stable typed output, unit tests, contract tests, PSU context coverage, and an opt-in live sandbox test before proceeding to the next dependency group.

### Slice A — Authoring pattern and core ticket reads

1. `Get-FreshServiceLocation`
2. `Get-FreshServiceTicket`
3. `Search-FreshServiceTicket`
4. `Get-FreshServiceTicketField`

This slice proves single-object reads, bounded lists, standard pagination, filters, optional embeds, and cached field definitions.

### Slice B — Form and report dimensions

1. `Get-FreshServiceAgentGroup`
2. `Get-FreshServiceDepartment`
3. `Get-FreshServiceAgent`
4. `Get-FreshServiceRequester`

This slice proves cached and uncached reference reads, report labels, requester lookup, and permission boundaries.

### Slice C — Asset capabilities

1. `Get-FreshServiceAssetType`
2. `Get-FreshServiceAsset`
3. `Get-FreshServiceAssetAssignmentHistory`

These are general-purpose reads for PSU asset pages, reports, and automations. `Get-FreshServiceAsset` supports exact identifiers and bounded search/filter forms needed by the app; it does not multiplex components, requests, contracts, or relationships. Assignment history is feature-gated and fails with a distinct normalized error when unavailable.

### Slice D — Fulfillment, approvals, activity, and policy

1. `Get-FreshServiceRequestedItem`
2. `Get-FreshServiceTask`
3. `Get-FreshServiceRequestApproval`
4. `Search-FreshServiceApproval`
5. `Get-FreshServiceTicketActivity`
6. `Get-FreshServiceSLAPolicy`
7. `Get-FreshServiceBusinessHour`

This slice proves parent-scoped reads, global filtered reads, feature gates, and ticket-activity token pagination.

### Exit criteria

- All 18 read commands use only the shared contracts and request pipeline.
- List and search commands stream typed records under page and record limits.
- Cached and permission-filtered resources follow their documented boundaries.
- Exact manifest exports contain only completed reads; no placeholder command is exported.
- Unit, contract, PSU, and opt-in live tests pass for every read.

## 10. Phase 6 — Mutation commands

Implement writes only after their lookup, validation, credential-selection, and error dependencies are proven by Phase 5.

### Implementation order

1. `New-FreshServiceTicket`
2. `Set-FreshServiceTicket`
3. `Add-FreshServiceTicketNote`
4. `Set-FreshServiceAsset`

`Set-FreshServiceAsset` is a general controlled update command for PSU apps and automations. It supports ordinary asset fields such as owner, department, location, state, assignment date, and approved type-specific values. It does not create, delete, restore, permanently delete, move, or synchronize assets with a named external system.

### Required mutation controls

- `SupportsShouldProcess` and meaningful `ConfirmImpact`.
- Focused parameters and one endpoint operation per command.
- Exact request-body contract tests that include only caller-supplied changes.
- `-WhatIf` performs no HTTP request or audit success event.
- Interactive writes use the selected personal credential; schedules and background automations use the named system credential.
- Ambiguous delivery never triggers an unsafe replay and returns a normalized uncertain-outcome error.
- Live tests use disposable development records and verify Freshservice attribution and audit behavior.

### Exit criteria

- All four mutations use only the shared contracts and request pipeline.
- Create, update, close, note, and asset-update scenarios have focused unit, contract, PSU, and opt-in live coverage.
- Note authorship matches the recorded Phase 1 result for both personal and system credentials.
- The manifest exports exactly the accepted 22 commands and no aliases.
- Help and `SUPPORTED_COMMANDS.md` match actual syntax and typed output.

## 11. Phase 7 — Consumer examples and PSU integration validation

Validate the module through small example scripts and PSU integration tests. Building production pages, reports, schedules, databases, or automations is outside this repository.

### Deliverables

- Read-only examples for ticket, approval, task, activity, reference-data, and asset queries.
- Mutation examples for ticket creation, ticket updates, notes, and asset updates, including `-WhatIf` where supported.
- Streaming examples wrap list calls in `try`/`catch`, discard or reconcile partial output after a terminating error, and mark a report run complete only after successful command completion.
- PSU integration fixtures proving personal and system attribution, stage isolation, timeout behavior, and reused-runspace isolation.
- Examples consume and display results only; they do not implement production UI, persistence, schedules, or organizational workflows.

### Exit criteria

- Every command is exercised by an example or PSU integration fixture using only the public module surface.
- Interactive calls remain within the measured PSU timeout and API reserve.
- System and personal execution are attributed correctly.
- Mutation examples use safe preview where supported; access to the consuming example is controlled by PSU.
- No example reaches into private module functions or implements consumer-owned persistence or scheduling.

## 12. Phase 8 — Package and release the module

### Deliverables

- Run unit and contract tests on the production PowerShell 7.6 and operating-system matrix.
- Run PSU integration tests in a credentialed isolated pipeline.
- Run live Freshservice tests separately and opt-in against disposable dev records.
- Validate the sample PSU-variable configuration, built-in-vault references, limiter behavior, and cache behavior.
- Validate `PSU_SETUP.md` from a clean development environment, including explicit-version import, configuration, identity, audit capture, and smoke tests.
- Generate focused command help and publish concise breaking-release notes.
- Set `ModuleVersion = '1.0.0'`, replace the inherited module GUID, and verify fork-owned manifest metadata.
- Produce a deterministic versioned module archive and SHA-256 checksum, attach both to the matching tagged GitHub release, and do not publish to the PowerShell Gallery.
- Validate clean install, upgrade from the preceding FreshservicePSU artifact, explicit-version import, reused-runspace replacement, and rollback before publishing the breaking release.

### Exit criteria

- Default CI requires no PSU or Freshservice credentials.
- Credentialed CI proves personal attribution, system execution, stage isolation, unknown-identity denial, and runspace isolation.
- The manifest, command reference, prune list, help, endpoint decisions, and actual exported commands agree exactly.
- The tagged release version, manifest version, archive directory, checksum, and release notes agree; a clean machine can install and import the artifact without repository files.
- All architecture definition-of-done items pass.

## 13. Cross-phase quality gates

Every implementation phase runs all applicable checks:

- PSScriptAnalyzer and formatting checks.
- `Test-ModuleManifest`, clean import, and explicit export comparison.
- Offline unit and contract tests.
- Secret-redaction tests for every new log, audit, and error path.
- `ShouldProcess` and `-WhatIf` tests for mutations.
- No direct HTTP calls outside the shared request helper.
- No module/global credential or execution-context state.
- No public tenant, stage, base URI, workspace, credential, or secret-selection parameter.
- Documentation and endpoint decisions updated with the same change.

Credentialed tests never run automatically on forks or untrusted branches.

## 14. Testing lanes

Four lanes with different inputs and trust levels. A phase is complete only when every lane it touches passes.

| Lane | Requires | Runs | Proves |
| --- | --- | --- | --- |
| Unit (`tests/Unit`) | Nothing | Every change | Parameter validation, URI and body construction, error mapping, and decision logic under injected clock and random sources. |
| Contract (`tests/Contract`) | Nothing; recorded fixtures only | Every change | Exact request shape and exact typed output for each command, including envelope extraction, `PSTypeName`, pagination termination, retry, and `429` behavior. |
| Architecture (`tests/Architecture`) | Nothing | Every change | Repository-wide invariants: naming boundary (§12 of the architecture), manifest exports, no direct HTTP outside the pipeline, no global state, no banned APIs, and documentation consistency. |
| Integration (`tests/Integration`) | PSU instance, or Freshservice sandbox | Opt-in, credentialed pipeline only | Identity, attribution, stage isolation, runspace isolation, timeout behavior, endpoint entitlement, and live response shape. |

Rules that apply across the lanes:

- The first three lanes are the default CI path and must never require PSU, a secret, or a tenant. A test that cannot run offline belongs in Integration.
- Contract fixtures are sanitized recorded responses. They carry no keys, tokens, personal data, or tenant hostnames, and a fixture is refreshed rather than hand-edited when the vendor shape changes.
- Every mutation has a `-WhatIf` test asserting that no HTTP request and no success audit event occurred.
- Every new log, audit, or error path has a redaction test before the path ships.
- A defect in `CURRENT_STATE_REVIEW.md` is closed by a regression test naming its finding ID, so `F1`-style fabricated success cannot silently return.
- Live tests use disposable development records and clean up, or explain in the test why cleanup is unnecessary.

## 15. Documentation update rules

Documentation is a phase deliverable, not a release task. It changes in the same commit as the behavior it describes.

| When this changes | Update | Enforced by |
| --- | --- | --- |
| The public command set | `SUPPORTED_COMMANDS.md`, §2 of this plan, `COMMAND_PRUNE_LIST.md`, `FreshservicePSU.psd1` | `tests/Documentation.Tests.ps1` compares all three inventories and the exported count |
| A design decision or security invariant | `ARCHITECTURE.md`, and the settled-decisions table when the decision is closed | Review; architecture tests where the invariant is mechanical |
| Installation, PSU configuration, identity setup, audit capture, upgrade, or rollback | `PSU_SETUP.md` after the architecture decision is updated | Phase 8 clean-environment walkthrough and link tests |
| An open question is answered | Move the answer into the architecture, this plan, or the command reference, then delete the row from `OPEN_QUESTIONS.md` | Phase exit criteria naming the Q-ID |
| Target scope for an endpoint family | `FRESHSERVICE_API_V2_ENDPOINT_COMPARISON.csv` decision column, and `CLAUDE.md` when a scope constraint itself changes | Documentation test requires every CSV row to carry an `Add`/`Skip`/`Conditional` decision |
| Command syntax, parameters, or output | Comment-based help, then regenerate `docs/en-US/` | Phase 8 compares generated help against actual syntax |
| A command is removed | Delete its help topic, tests, and examples in the same change; record the removal in `COMMAND_PRUNE_LIST.md` and the release notes | Help-topic set equals the exported command set; no non-evidence file references a removed name |
| Legacy evidence | `CURRENT_STATE_REVIEW.md` and `API_V2_COVERAGE_MATRIX.md` | Review only; these are evidence documents and never define target behavior |
| Vulnerability reporting or secret-handling policy | `SECURITY.md` | Review and relative-link tests |

Additional rules:

- **Authority resolves conflicts.** `ARCHITECTURE_MODERNIZATION_PLAN.md` states the authority order. When two documents disagree, correct the lower-authority document in the same change rather than leaving both.
- **Record every break.** Backward compatibility is not a constraint, but each removed command, renamed parameter, and changed output shape is named in the release notes so migration is a known cost.
- **No completed-product wording ahead of the code.** A document describes either accepted intent or shipped behavior, and says which.
- **Counts are generated or tested, never hand-tallied.** The 22-command figure and the endpoint-coverage counts are assertions in the documentation test; Phase 8 generates the coverage matrix from the command list.

## 16. Release risks

| Risk | Control |
| --- | --- |
| PSU surface exposes no trustworthy human initiator | Use an authenticated App/API boundary or classify the operation as system execution. |
| Pooled runspace leaks prior identity | Resolve context per operation and run concurrency integration tests. |
| Broken personal secret silently changes attribution | Fail without fallback when a personal mapping exists. |
| Shared account limit is exhausted by pages and schedules | Shared endpoint-aware limiter, PSU concurrency caps, schedule staggering, and an interactive reserve. |
| Non-idempotent mutation is replayed after ambiguous failure | Refuse unsafe replay and return a normalized uncertain-outcome error. |
| Asset update changes the wrong record | Require exact identifiers, validate lookup uniqueness in the PSU consumer, use `ShouldProcess`, and send only changed properties. |
| Module upgrade changes tenant or secret resolution | External validated configuration, fail-closed selection, and isolated prod/dev environments. |
| Unsupported legacy behavior returns accidentally | Clean module skeleton, explicit exports, architecture searches, and no compatibility layer. |
| PowerShell runtime drifts | Require 7.6 and test the serviced production patch in CI and PSU. |

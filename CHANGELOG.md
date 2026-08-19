# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## Fork lineage

This repository is maintained as a fork at
<https://github.com/cbreland-DLR/FreshservicePSU>. The release history below,
through version 0.1.6, belongs to the original
<https://github.com/flycastpartnersinc/FreshservicePS> project. Changes made in
this fork are recorded above the inherited history.

## [Unreleased]

### Changed

- **Rate limiting is now reactive.** The module no longer meters requests before
  sending them. It sends, and on a `429` honors `Retry-After` and retries within
  the policy budget. Rate headers remain on the response envelope as telemetry
  and gate nothing.

  The proactive shared limiter is removed: `Get-`/`Register-FsuRateLimiterProvider`,
  `Request-`/`Confirm-`/`Clear-FsuRateLimitReservation`, `New-FsuRateLimiterKey`,
  and `New-FsuInMemoryRateLimiterProvider`. `Invoke-FsuRequest`,
  `Invoke-FsuPagedRequest`, `Invoke-FsuNumberedPagedRequest`, and
  `Invoke-FsuTokenPagedRequest` drop their `-RateLimiterProvider`,
  `-EndpointClass`, `-Limit`, and `-EstimatedCost` parameters. No public command
  signature changes.

  The reason: the Freshservice limit is account-wide and shared with consumers
  this module cannot observe, so local reservation accounting could never be
  authoritative — a cross-process limiter bought consistency among PSU workers
  rather than correctness against the real budget, while gating every command on
  a provider that was never implemented. This reverses the shared-limiter
  decision recorded in ARCHITECTURE.md "Rate limits" and withdraws Q15.

  Accepted consequence: two PSU worker processes can each approach an endpoint
  sublimit and one absorbs a `429`, costing a refused request and a wait.

- The noninteractive retry budget is now 180 seconds (was 120) so a full
  minute-level rate-limit window plus the retried request fits inside it.
  Interactive stays at 20 seconds deliberately, so a PSU page surfaces a `429`
  as a renderable error instead of hanging for a minute.

- `tools/Get-PsuIdentityEvidence.ps1` is now strictly read-only. Its Q15
  cross-process probe (`-RunSharedStateTest`, `-SharedStateProbeId`,
  `-SharedStateRole`, `-MutexHoldSeconds`) is removed along with the
  `SharedState` report field, the matching rendering in
  `ConvertFrom-FsuEvidenceReport.ps1`, and the `tools/README.md` run matrix
  rows and worked examples. The probe existed only to validate the withdrawn
  shared limiter; taking an OS-named mutex and writing a PSU cache entry was
  the tool's only writing mode.

  Note for whoever picks up PSU-cache-backed reference data: the cache
  round-trip and restart-persistence checks went with it. That question is
  still live for the reference cache, and a probe for it should be rebuilt
  against the actual cache implementation rather than restored from here.

- `docs/OPEN_QUESTIONS.md` now lists only genuinely open items: Q1, Q2, Q3, Q7,
  Q8, and Q9. Q13 (per-command typed output) is closed as answered — the output
  contract for every shipped command is in `SUPPORTED_COMMANDS.md` §6.5–§6.21,
  each `docs/en-US` topic states or references it, and contract tests assert the
  property names and `PSTypeName`. Q15 is closed as withdrawn. The now-dangling
  `Q13` tags were removed from the command reference section headings, the help
  topics, the architecture, and the plan; the tables and contracts themselves are
  unchanged. CHANGELOG entries for earlier releases keep their original wording.

### Removed

- The entire inherited command surface: all 165 public commands, the on-disk
  multi-tenant connection-profile model (`Connect-Freshservice`,
  `New`/`Get`/`Set`/`Remove-FreshServiceConnection`), the
  `Invoke-FreshworksRestMethod` transport, the generated `FS*` aliases, and the
  165 generated help topics. The 22-command contract is implemented
  incrementally; `Get-FreshServiceLocation` is the first exported command.

### Changed

- Module import has no side effects: no automatic connection, no profile or
  config-file read, no global variables, no banner.
- The manifest export list is explicit and no longer wildcards aliases,
  variables, or cmdlets. It grows only when a command meets its slice exit
  criteria.
- The PSU limiter evidence probe now uses a shared cache key, measurable
  cross-process mutex contention, explicit cleanup, and pre/post-restart roles
  so Q15 can be answered conclusively.
- Architecture tests that use Pester `-ForEach` on violation lists tolerate an
  empty list so the offline gate runs on Pester 6 as well as 5.7.

### Added

- `tools/Get-PsuIdentityEvidence.ps1`: operator tooling outside the module
  for collecting sanitized identity and deployment evidence. Reports are
  not committed. See `tools/README.md` for the run matrix and instructions.
- `tools/Get-FreshserviceSandboxEvidence.ps1`: guarded sandbox probes for note
  authorship, approval search, asset assignment history, pagination, and the
  correlation header without recording credentials or response values.
- `tools/ConvertFrom-FsuEvidenceReport.ps1`: closed-schema conversion of raw
  evidence JSON into temporary, review-only Markdown; it never edits the open
  question registry or declares a conclusion.
- A separate `./build.ps1 -Task Tools` gate with mocked offline tests for
  operator-tool syntax, formatting, analysis, sanitization, and safety guards.
- Offline test lanes (`tests/Unit`, `tests/Contract`, `tests/Architecture`) and
  architecture checks enforcing the naming boundary, forbidden runtime APIs,
  transport confined to `Private/Http`, and documentation alignment.
- Configuration validation (`Test-FsuConfiguration`) and the `Freshservice.Configuration`
  contract defined in ARCHITECTURE.md §7.
- Error normalization (`ConvertTo-FsuNormalizedError`), error construction
  (`New-FsuErrorRecord`), and response envelope (`New-FsuResponse`) contracts;
  20 documented Freshservice error codes and 10 HTTP statuses map to stable
  normalized ErrorCategory and FullyQualifiedErrorId.
- Retry policy (`New-FsuRetryPolicy` and `Get-FsuRetryDecision`) enforcing the
  ARCHITECTURE.md §11 budget rule under injectable clock; pure, testable decision
  logic with no side effects.
- Audit event construction (`New-FsuAuditEvent`) and emission (`Write-FsuAuditEvent`)
  from a closed 12-field allowlist; events tagged `FreshservicePSU.Audit` on the
  information stream only, never in success output.
- Unit tests for each of the above contracts.
- PSU host adapter (`Get-FsuHostInvocation`, `ConvertTo-FsuExecutionPrincipal`)
  that normalizes documented Entra SAML and OIDC claims into
  `Freshservice.ExecutionPrincipal`, with fail-closed unauthenticated App
  callers and system identity for schedules and claimless API tokens.
- Credential selection (`Resolve-FsuCredential`, `Get-FsuSecret`) and
  per-operation context creation (`Get-FsuExecutionContext`). Secrets are
  resolved only after identity validation, never cached, and never included
  in formatted or serialized context output.
- Shared request pipeline: `Send-FsuHttpRequest` (the only HttpClient call),
  `Invoke-FsuRequest`, and `Invoke-FsuPagedRequest`. Tests inject a transport
  so the offline gate never touches the network. Mutations that time out or
  get a 5xx return an uncertain-outcome error instead of fabricated success.
  Paging follows `Link` only and surfaces `FreshservicePSU.PartialResults`
  when a later page fails.
- `Get-FreshServiceLocation`, the first exported command: one location by
  `-Id` or a bounded list with optional `-Name` filter. Output type
  `FreshservicePSU.Location` follows the Q13 table in
  `docs/SUPPORTED_COMMANDS.md` §6.5.
- `Register-FsuRateLimiterProvider` / `Get-FsuRateLimiterProvider` so public
  commands fail closed when no limiter is registered instead of sending
  unlimited.
- `Get-FreshServiceTicket`: one ticket by `-TicketId` or a bounded list with
  requester, email, updated-since, or predefined filter. Opt-in embeds are
  `Requester`, `Stats`, and `Conversations` (conversations only on a
  single-ticket read). Output type `FreshservicePSU.Ticket` follows the Q13
  table in `docs/SUPPORTED_COMMANDS.md` §6.6.
- `Search-FreshServiceTicket`: `GET /tickets/filter` with a validated
  query, numbered paging, and the same `FreshservicePSU.Ticket` contract.
  Empty, unbounded, malformed, overlong, and `workspace_id` queries fail
  before transport.
- `Get-FreshServiceTicketField`: `GET /ticket_form_fields` for dynamic
  forms and choice resolution. Optional `-Id` / `-Name` select one field
  from the list. Output type `FreshservicePSU.TicketField` follows the Q13
  table in `docs/SUPPORTED_COMMANDS.md` §6.7. Phase 5 Slice A is complete.
- `Get-FreshServiceAgentGroup`, `Get-FreshServiceDepartment`, and
  `Get-FreshServiceAgent`: Slice B assignment and form-dimension reads.
  Department supports `-Name`; agent supports `-Email`, `-Active`, and
  `-State`. None send `workspace_id`. Q13 tables are §6.8–§6.10.
- `Get-FreshServiceRequester`: the last Slice B command. `-Id` or a
  bounded list with optional `-Email`. Maps `primary_email` to `Email`.
  Does not send `include_agents` or `workspace_id`. Output type
  `FreshservicePSU.Requester` follows the Q13 table in
  `docs/SUPPORTED_COMMANDS.md` §6.11. Phase 5 Slice B is complete.
- `Get-FreshServiceAsset`: Slice C device inventory read. Four
  mutually exclusive lookups: `-DisplayId` (`GET /assets/{display_id}`),
  `-AssetTag`, `-SerialNumber`, and a bounded `-Filter`
  (`GET /assets?filter=`). Rejects empty, unbounded, malformed,
  overlong, and `workspace_id` filters. Does not reach components,
  requests, contracts, or relationships. Output type
  `FreshservicePSU.Asset` follows the Q13 table in
  `docs/SUPPORTED_COMMANDS.md` §6.12.
- `Set-FreshServiceAsset` and `Remove-FreshServiceAsset`: asset mutations
  shipped early for the owner workload. Update sends only bound ordinary
  fields (`ShouldProcess`, Update Asset limiter 160). Remove is a soft
  delete (`DELETE /assets/{display_id}`, ConfirmImpact High). Neither
  restores, permanently deletes, moves, or changes asset type. The
  accepted inventory is now 23 commands.
- `Get-FreshServiceAssetType` and
  `Get-FreshServiceAssetAssignmentHistory`: remaining Slice C reads.
  Asset types are `-Id` or a bounded list (`GET /asset_types`).
  Assignment history is parent-scoped
  (`GET /assets/{display_id}/assignment-history`) and remaps
  `require_feature` or HTTP 405 to
  `FreshservicePSU.Asset.AssignmentHistoryUnavailable`. Q13 tables are
  §6.13–§6.14. Phase 5 Slice C is complete.
- Slice D reporting reads: `Get-FreshServiceRequestedItem`,
  `Get-FreshServiceTask`, `Get-FreshServiceRequestApproval`,
  `Search-FreshServiceApproval`, `Get-FreshServiceTicketActivity`,
  `Get-FreshServiceSLAPolicy`, and `Get-FreshServiceBusinessHour`.
  Activity follows `next_page_url` tokens. Approval search requires
  `parent=ticket` plus one documented filter and remaps a missing
  feature to `FreshservicePSU.Approval.SearchUnavailable`. Q13 tables
  are §6.15–§6.20. Phase 5 is complete.
- Phase 6 ticket mutations: `New-FreshServiceTicket`,
  `Set-FreshServiceTicket`, and `Add-FreshServiceTicketNote`. Create
  requires requester email or ID, subject, and description. Update
  sends only bound fields; closing is `-Status`. Notes accept body,
  privacy, and notify emails and do not send `user_id`. All three
  support `ShouldProcess`. Custom ticket fields are validated against
  `Get-FreshServiceTicketField`. The accepted 23-command surface is
  now exported.
- Phase 7 consumer examples in `examples/`: bounded reference, ticket,
  asset, and policy reads, plus `-WhatIf` ticket and asset mutation
  previews. List examples emit results only after the command
  completes. Opt-in PSU isolation fixtures are in
  `tests/Integration` and are not part of default Validate.

### Planned breaking release

- Rebuild the module as FreshservicePSU `1.0.0` for PowerShell Universal and
  PowerShell 7.6.
- Replace the inherited connection-profile and command surface with the focused
  22-command contract documented in `docs/SUPPORTED_COMMANDS.md`.
- Distribute checksummed GitHub release artifacts rather than publishing the
  fork to the PowerShell Gallery.

This section records accepted intent until implementation lands. Release notes
will enumerate removed commands, changed parameters, and output contracts before
`1.0.0` is tagged.

## [0.1.6]

### Fixed

- The $IsWindows variable isn't available in older PS versions.  The $FreshServiceConfigPath was using the incorrect variable path.  Updated to check for $env:OS to support pre-core Powershell versions.

## [0.1.5]

### Fixed

- Fixed bug in FreshservicePS.psm1 import not correctly importing functions.

## [0.1.4]

### Added

- Additional support for Workspaces.
- Get-FreshServiceWorkspace cmdlet to list Workspaces.
- Filtering for workspace_id:

  - Get-FreshServiceAgent
  - Get-FreshServiceAsset
  - Get-FreshServiceTicket
  - Get-FreshServiceChange
  - Get-FreshServiceProblem
  - Get-FreshServiceRelease
  - Get-FreshServiceBusinessHour
  - Get-FreshServiceSolutionCategory
  - Get-FreshServiceCatalogCategory
  - Get-FreshServiceCatalogItem
  - Get-FreshServiceCustomObject

- Move methods and options for Workspaces:

  - Set-FreshserviceTicket
  - Set-FreshserviceProblem
  - Set-FreshserviceChange
  - Set-FreshserviceRelease
  - Set-FreshServiceAsset

- Create items in Workspaces:

  - New-FreshServiceAsset
  - New-FreshServiceTicket
  - New-FreshServiceChange
  - New-FreshServiceProblem
  - New-FreshServiceRelease

- Agent licensing for Workspace assignment and License Type:

  - New-FreshServiceAgent
  - Set-FreshServiceAgent

- Updated the New-FreshserviceConnection to only require tenant and apikey.  If a friendly name is not provided, it will use the tenant name.  The first connection will be set to the default.  These settings are to make connection simple for new users.  Converted the Default parameter from Boolean to Switch.

- Originally Freshservice did not support custom statuses and there was a validation done in the cmdlet (e.g. ValidateSet).  Removed the validation to allow custom statuses for tickets.  Current valid values can be viewed with Get-FSTicket -Fields.

- Updated Invoke-FreshserviceRestMethod to append UTF-8 header and set 'application/json; charset=utf-8' and default ContentType.

- Updated Invoke-FreshserviceRestMethod to include -UseBasicParsing for Invoke-WebRequest for all calls to support backwards compatibility for Server Core and older PS versions.

### Fixed

- Filter pagination loop logic.  There is no relative link to perform pagination, updated logic to manually increment page until there is no content returned.

  - Get-FreshServiceAgent
  - Get-FreshServiceAsset
  - Get-FreshserviceTicket
  - Get-FreshServiceProjectTask
  - Get-FreshServiceRequester

## [0.1.3]

### Added

- Removed mandatory parameter for Environment in New-FreshserviceConnection and defaulted to Production

### Fixed

- Moved the if statement for should process to ensure the entire url is built for WhatIf for Remove-FreshserviceAsset

## [0.1.2]

### Fixed

- Updated cmdlets custom_fields with data type object[] to object

## [0.1.1]

### Fixed

- Invoke-FreshServiceRestMethod updates to handle 429 retry and automatically sleep when rate limit is reached.
- Updated incomplete examples help in New-FreshServiceOnboardingRequest and Set-FreshServiceOnboardingRequest

### Added

- Invoke-FreshserviceRestMethod updated to have artificial throttling to ensure module commands do not consume all api credits.  Progressively adds a Sleep after calls from 5 seconds @ 70% consumed to 15 seconds @ 80% consumed to 30 seconds at 90% consumed to avoid 429.
- Connect-Freshservice added a -NoThrottle to override the artificial throttling.

## [0.1.0] 5/24/2023

- Initial release

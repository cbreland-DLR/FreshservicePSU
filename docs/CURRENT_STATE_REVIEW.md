# FreshservicePSU current-state review

- **Review date:** 2026-08-12
- **Reviewed commit:** `82f7141` on `dev`
- **Executed with:** PowerShell 7.6.4 on Ubuntu 24.04
- **Target architecture:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Remediation sequence:** [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)

This document records evidence about the legacy implementation. It is not the target design or implementation checklist.

## 1. Severity

| Severity | Meaning |
| --- | --- |
| S1 | Credential exposure or silent data loss |
| S2 | Incorrect behavior, security-boundary failure, or PSU blocker |
| S3 | Maintainability, performance, testability, or hygiene issue |

## 2. Executive summary

The module has broad Freshservice API v2 coverage, but its architecture assumes an interactive Windows PowerShell session with a disk-backed connection profile and mutable per-runspace state. That model conflicts with PSU's authenticated, long-lived, pooled execution environment.

The most urgent defects are independent of the redesign:

- A `429` can silently discard create/update/delete work.
- Verbose output can persist usable API credentials.

The remaining structural issues justify a clean PowerShell 7/PSU-first major version: import side effects, ambient connection state, duplicated transport policy, platform-specific URI and secret behavior, live-only tests, untyped responses, accumulated pagination, and incomplete error handling.

## 3. Inventory

| Measure | Verified value |
| --- | --- |
| Public command files/functions | 165 |
| Private transport helpers | 1 |
| Dot-sourced files on import | 166 (165 public, 1 private) |
| Public source lines | Approximately 31,500 |
| Comment-based help | Approximately 12,900 lines |
| Inline connection guards | 155 files |
| Manifest `PrivateData` reads | 157 sites |
| Hand-written pagination loops | 47 files |
| Inline `ConvertFrom-Json` | 117 sites |
| `$PSBoundParameters` body mapping | 72 files |
| Commands declaring `OutputType` | 6 |
| `System.Web.HttpUtility` | 55 occurrences across 53 files |
| Public files with PowerShell-version branches | 14 |
| `UseBasicParsing` | 1 occurrence |
| `ServicePointManager` mutation | 1 occurrence |

The current design makes a transport change fan out across roughly 50–155 public files.

## 4. Findings

### F1 — `429` silently discards mutations (S1)

`FreshservicePSU/Private/Invoke-FreshworksRestMethod.ps1:225-238` catches HTTP 429, sleeps, and returns a fabricated object whose content is null and whose `Link` header points back to the same URI.

Paged reads may continue because they follow the fabricated link. Mutation commands invoke the wrapper once, and they fail in two distinct ways.

**Silent `$null` — most `New-*` and `Set-*`.** These return only when `Content` is present, for example `FreshservicePSU/Public/Tickets/New-FreshServiceTicket.ps1:475-484`. The result is `$null`, no terminating error, and no completed operation.

**Fabricated success — 41 commands.** Every `Remove-*` (32), every `Restore-*` (6), plus `Set-FreshServiceContract`, `Set-FreshServiceProject`, and `Set-FreshServiceRequestApproval` target endpoints returning `204 No Content`, so they synthesize a result *unconditionally*, with no `Content` gate:

```powershell
$results = Invoke-FreshworksRestMethod @params

[PSCustomObject]@{
    id     = $id
    status = "success {0}" -f $results.StatusCode
}
```

The synthetic 429 object has no `StatusCode` property, so the emitted status is the literal string `"success "`. The command reports success for a delete or restore that never happened. This is worse than the `$null` case: a caller that checks the result is affirmatively misinformed. The help text documents the fabrication as intended ("artificial response with id and status containing status code is returned for tracking"), so it does not read as a defect on inspection.

Target control: the clean rebuild removes the legacy transport and synthetic-success paths. The shared request pipeline provides bounded retry, normalized errors, and explicit uncertain-outcome handling; patching the legacy commands individually is not part of the accepted plan.

### F2 — Verbose output exposes credentials (S1)

- `FreshservicePSU/Private/Invoke-FreshworksRestMethod.ps1:149` logs the base64 authorization token.
- `FreshservicePSU/Private/Invoke-FreshworksRestMethod.ps1:171-183` logs every header, including `Authorization`.
- `FreshservicePSU/Public/Connection/Get-FreshServiceConnection.ps1:97` logs the decrypted API key.

PSU persists job and verbose output. A verbose execution can therefore place a reusable credential in durable logs.

Target control: remove the legacy transport during the clean-module phase and require redaction tests for every new logging, error, and audit path.

### F3 — Missing connection uses `break` instead of a terminating error (S2)

`FreshservicePSU/Private/Invoke-FreshworksRestMethod.ps1:143-145` warns and calls `break` from its `begin` block. In a caller with an enclosing loop, this can terminate that loop instead of producing a catchable error.

Target control: the clean rebuild removes this connection guard; the new public boundary fails closed with a terminating error before HTTP execution.

### F4 — Every request mutates process-wide TLS state (S2)

`FreshservicePSU/Private/Invoke-FreshworksRestMethod.ps1:187-189` sets `ServicePointManager.SecurityProtocol` to TLS 1.2 on every call.

In a long-lived PSU process this affects unrelated code, can remove newer protocol choices, and does not control the .NET Core `HttpClient` stack used by the target runtime.

Target control: remove the legacy transport during the clean-module phase and prohibit process-global transport state through architecture checks.

### F5 — The saved credential store is unsuitable for PSU (S1/S2)

`FreshservicePSU/Public/Connection/New-FreshServiceConnection.ps1:134` serializes a `SecureString` into a profile under `$env:APPDATA`.

- On Windows, DPAPI current-user scope binds the data to the creating identity, which is generally not the PSU service identity.
- On Linux/macOS, the legacy conversion does not provide equivalent encrypted-at-rest protection; the reviewed output could be decoded to the original value.

Required action: remove the profile system and resolve secrets from the approved PSU vault.

### F6 — Authentication is inseparable from the disk profile (S2)

`FreshservicePSU/Public/Connection/Connect-FreshService.ps1:45-71` accepts a profile name but no API key, `SecureString`, credential, vault reference, or environment source. PSU must reproduce the profile inside the service identity to connect.

Required action: delete `Connect-FreshService`; public commands use the trusted PSU adapter and internal context.

### F7 — Connection state is ambient, per-runspace, and single-tenant (S2)

The manifest's `PrivateData` holds the base URI, token, headers, and throttle state. `Connect-FreshService` writes it, and 157 public sites read it.

Under pooled PSU execution:

- A connect in one runspace does not reliably configure another.
- State retained in a reused runspace can affect a later caller.
- Commands cannot explicitly address concurrent contexts.
- Import-time auto-connect makes tenant selection depend on filesystem and module-load state.

Required action: fail-closed PSU boundary and ephemeral per-operation context with no module credential cache.

### F8 — Import has disk, network, global-scope, alias, and console side effects (S2/S3)

`FreshservicePSU/FreshservicePSU.psm1`:

- Defines global module/config variables at lines 6–14.
- Creates an `FS` alias for every function with `-Force` at lines 22–26.
- Reads profiles and automatically connects at lines 33–45.
- Emits warnings/banners through the connection path.

Executed import exported 165 functions and 166 aliases and took approximately 0.9 seconds for 166 dot-sourced files.

Required action: deterministic loading, manifest-owned exports, no automatic aliases, and side-effect-free import.

### F9 — Declared Windows PowerShell 5.1 support is partially broken (S3)

The manifest declares PowerShell 5.1, but:

- Header indexing in `Invoke-FreshworksRestMethod.ps1:193-194` reads the first character of a string-valued header under 5.1 rather than the full value.
- `Invoke-WebRequest -Form` requires PowerShell 6.1+, so 5.1 attachment paths warn and omit attachments.

Target control: the clean module declares PowerShell 7.6/Core and does not carry compatibility branches forward.

### F10 — Transport policy is duplicated across commands (S3)

Connection checks, query building, JSON conversion, body filtering, response extraction, and pagination are repeated throughout the public surface. A single transport change requires dozens of endpoint edits.

Required action: one request pipeline with URI, serialization, response, error, and pagination helpers.

### F11 — Response envelopes are inferred (S2)

List commands often take the first JSON property name after filtering `total`; single-object commands similarly select properties by position. A vendor-added envelope field can silently change returned data.

Required action: each command names its expected response property and returns a stable typed object.

### F12 — Freshservice error details are discarded (S2)

Non-429 failures rethrow the raw HTTP exception. Freshservice's structured `errors[]` entries—including field, code, and message—are not converted into actionable PowerShell errors.

Required action: normalize status, code, field, and message into stable error categories and identifiers.

### F13 — Paginated results accumulate in memory (S3)

Paged commands commonly capture the entire loop into a variable and emit it only at the end. Large queries delay first output and create memory spikes in a shared PSU host. Commands expose no consistent result cap.

Required action: stream each page, enforce record limits, and reject page numbers above the vendor's deep-pagination ceiling.

### F14 — Tests depend on a live production tenant (S3)

Most resource tests connect to `ItsFine_Prod` and create real records. There is no mocked unit/contract boundary. `azure-pipelines.yml` references the retired `vs2017-win2016` image, and there is no current default CI workflow.

Required action: unit/contract tests by default, isolated PSU integration tests, and opt-in disposable-tenant live tests.

### F15 — Throttling misses endpoint sublimits and actual request cost (S3)

The existing percentage ladder uses the account-wide total/remaining headers. Freshservice also enforces lower per-endpoint sublimits, so a ticket endpoint can return `429` while the aggregate calculation appears healthy.

The code does not read `X-RateLimit-Used-CurrentRequest` and does not verify `X-Freshservice-Api-Version`. Its inline sleeps are not bounded by the PSU caller's timeout.

The vendor's v2 policy describes current limits as minute-level and account-wide, while one header-description table retains hourly wording. The target tenant must be observed before configuring thresholds.

Required action: endpoint-aware shared throughput control, response-cost telemetry, API-version checks, and separate interactive/background retry budgets.

### F16 — Minor correctness and maintainability issues (S3)

| Item | Evidence | Effect |
| --- | --- | --- |
| Undefined verbose variable | `Connect-FreshService.ps1:81` references `$plainPass` | Misleading output |
| `ProgressAction` absent from body exclusions | Manifest common-parameter list | PowerShell 7.4+ value can enter request bodies |
| Caller header hashtable mutated | `Invoke-FreshworksRestMethod.ps1:133-136` uses `.Add()` | Reusing the same input can throw |
| Exports maintained manually | Manifest function list | Drift is possible without an architecture test |
| Module build compilation disabled | `psakeFile.ps1:3` | Import remains a large dot-source operation |
| Backslash in URI path segments | `New-FreshServiceNote.ps1:82`, `Set-FreshServiceNote.ps1:90`, `Get-FreshServiceNote.ps1:115` | `'{0}/{1}s/{2}\notes'`. **(executed)** `UriBuilder` normalizes `\` to `/`, so these work by accident; three occurrences indicate copy-paste lineage |
| Double slash in restore path | `Restore-FreshServiceProject.ps1:47` | `'{0}//pm/projects'` produces a doubled separator |
| Format string with unused argument | `Get-FreshServiceNote.ps1:112` | `"{0}/conversations" -f $uri.Path, $Id` passes an argument the format string has no placeholder for |
| Pagination forced on single-record fetch | `Get-FreshServiceNote.ps1:106,120` | `$enablePagination = $true` in both branches, so a fetch by `-Id` still sends `page`/`per_page` |

## 5. Test and static-analysis assessment

The current suite is useful as a manual live-tenant acceptance harness, but it is not a safe or reliable default regression suite. The review found 36 test files and 336 literal `It` blocks. Thirty-two files connect to the hard-coded `ItsFine_Prod` profile, the suite contains 90 create/update/delete calls, and no Freshservice command is mocked.

### Executed checks

| Check | Result |
| --- | --- |
| PowerShell parser | 206 source, test, module, and data files; 0 parse errors |
| `Test-ModuleManifest` | Passed; version 0.1.6 with 165 exported functions |
| Module import on PowerShell 7.6.4 | Passed; 330 commands including generated aliases |
| Offline formatting tests | 2 passed, 0 failed |
| PSScriptAnalyzer, module | 30 findings: 2 errors, 22 warnings, 6 informational |
| PSScriptAnalyzer, tests | 4 warnings |

The full live suite was not executed during this review because discovery and setup connect to a named tenant and perform destructive operations. The local build wrapper was also not executed because its pinned `psake` and `PowerShellBuild` dependencies were not installed; installing dependencies was outside the read-only review.

### Test-suite defects

**Forty-six assertions do not execute the command under test.** They wrap a command in a script block and pipe that object to `Should -Not -BeNullOrEmpty`, for example:

```powershell
{ Get-FreshServiceAgent -fields } | Should -Not -BeNullOrEmpty
```

The assertion succeeds because the script block itself is non-null. Script blocks are appropriate for `Should -Throw` and `Should -Not -Throw`; result assertions must invoke the command directly.

**Live mutations occur during discovery.** Resource files commonly call `Connect-FreshService` and create fixtures in `BeforeDiscovery`. Discovery can therefore modify the tenant even when selected tests will not run. Tenant activity belongs in `BeforeAll`, after an explicit live-test opt-in guard.

**Cleanup is not failure-safe.** The suite has no `AfterEach`, `AfterAll`, or `finally` cleanup. If setup or an intermediate assertion fails, disposable records can remain in the tenant.

**There is no offline transport boundary.** No tests mock `Invoke-FreshworksRestMethod`, assert request URIs or bodies, exercise response/error normalization, or verify `ShouldProcess`. There is also no code-coverage configuration or threshold.

**Help validation depends on the network.** `Help.tests.ps1` sends an HTTP request for every help link. Link availability should be a separate scheduled check rather than part of deterministic pull-request validation.

### Static-analysis defects

The two analyzer errors are both credential-handling findings: `New-FreshServiceConnection.ps1:134` and `Set-FreshServiceConnection.ps1:166` convert plaintext API keys to `SecureString`. `Set-FreshServiceConnection.ps1:165` additionally writes the supplied API key to verbose output. This is an S1 issue and must be corrected with the other credential-log paths in F2.

The most important correctness warning is `Get-FreshServiceProblem.ps1:177`: `workspace_id` is declared but never added to the request. Other findings cover wildcard exports, global variables, four inaccurate `OutputType` declarations, trailing whitespace, and completion-script parameters that need either targeted suppression or refactoring.

The repository does not contain a `PSScriptAnalyzerSettings.psd1`, and analysis is not a build or CI task. The recursive analyzer invocation also raised an internal null-reference error after returning findings; per-file analysis completed successfully and produced the totals above. CI should use the per-file form until the tool/configuration combination is updated and verified.

### Recommended test and quality gates

1. Correct the 46 non-executing assertions and add an architecture test that rejects this pattern.
2. Create default-offline unit and contract suites around the transport boundary. Assert URI, method, headers, serialization, pagination, retry behavior, normalized errors, secret redaction, and `ShouldProcess` behavior.
3. Tag and isolate `Unit`, `Contract`, `PSU`, and `Live` suites. Require explicit environment opt-in for live tests and inject the connection/tenant rather than naming `ItsFine_Prod` in source.
4. Move all external activity out of `BeforeDiscovery`; register cleanup immediately after fixture creation and guarantee it in `AfterAll` or `finally`.
5. Commit analyzer settings with intentional rule selection and narrowly documented suppressions. Fail CI on errors and on unsuppressed warnings.
6. Replace the retired `vs2017-win2016` job with the supported PowerShell 7.6 OS matrix. Run parser, manifest/import, analyzer, formatting, help-structure, export-drift, unit, and contract checks on every change.
7. Keep PSU integration and live Freshservice tests in separate protected, credentialed jobs against disposable records. Run network link validation on a schedule.
8. Publish Pester results and code coverage, then introduce a ratcheting coverage threshold as resource families move to the new transport pipeline.

## 6. Legacy runtime inventory

These items explain why the accepted plan replaces the legacy tree with a clean PowerShell 7.6 module instead of mechanically converting every file:

- Manifest minimum version and `Core` edition declaration.
- Fourteen public files containing version-dependent behavior.
- Fifty-five `System.Web.HttpUtility` occurrences across 53 files.
- `UseBasicParsing` and `ServicePointManager` compatibility code.
- PowerShell 7 HTTP exception/response/header types.
- URI paths built with filesystem semantics or backslashes.
- Multipart upload and JSON-depth behavior.
- UTF-8 encoding across source, configuration, fixtures, requests, and generated artifacts.
- Full-framework or Windows-only dependencies.
- PSU runtime selection and supported Windows/Linux CI matrix.

## 7. Finding-to-phase traceability

Phases refer to `IMPLEMENTATION_PLAN.md` §3. Per that plan's §14, each finding is closed by a regression test naming its ID, so a fix cannot silently regress.

| Finding | Phase that closes it |
| --- | --- |
| F1 synthetic `429` result | 4 pipeline retry and `429` policy; verified again in 6 for each mutation |
| F2 credential logging | 2 removes the legacy logging; 3 defines the safe-logging and audit contract |
| F3 `break` control flow | 2 removes the connection guard; 3 makes a missing context a terminating fail-closed error |
| F4 global TLS mutation | 2 — architecture checks reject `ServicePointManager` |
| F5 unsafe profile store | 2 removes the profile store; 3 defines vault-backed credential resolution |
| F6 profile-only authentication | 2 and 3 |
| F7 ambient runspace state | 3 resolves context per operation; 7 proves runspace isolation in PSU |
| F8 import side effects | 2 — clean module skeleton and side-effect-free import test |
| F9 broken 5.1 contract | 2 — `PowerShellVersion = '7.6'` and `CompatiblePSEditions = @('Core')` |
| F10 duplicated transport | 4 — every command uses the shared pipeline |
| F11 inferred response shape | 4 explicit envelope extraction; per-command contract tests in 5 and 6 |
| F12 discarded API errors | 4 — normalized error records preserving `code` and `field` |
| F13 accumulated pagination | 4 — page streaming under record and page caps |
| F14 live-only tests | 2 establishes the offline lanes; complete in 8 |
| F15 incomplete rate handling | 1 records documented and observed limits; 4 implements the endpoint-aware limiter |
| F16 minor issues | 2, 4, and the affected command slices in 5 and 6 |

## 8. Review conclusions

The resource-folder layout is not the core problem and can remain. The architecture should change around it:

- PSU owns the trusted identity and environment boundary.
- The module resolves an ephemeral per-operation context.
- One request pipeline owns all transport concerns.
- Resource families migrate incrementally, beginning with a reference CRUD family, then tickets/notes, then assets.
- The old connection and profile design is removed after all families migrate.

Per-user Freshservice API keys with an explicit system-account fallback are committed scope. Testing `user_id` behavior may document Freshservice semantics but does not alter the attribution design.

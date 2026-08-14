# FreshservicePSU target architecture

Unresolved deployment and command-contract decisions are tracked in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

- **Status:** Proposed
- **Date:** 2026-08-12
- **Runtime:** PowerShell Universal on PowerShell 7.6 LTS
- **Scope:** Standard Freshservice API v2, Enterprise plan, one tenant with isolated prod and dev environments
- **Implementation:** [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)
- **Current-state evidence:** [CURRENT_STATE_REVIEW.md](CURRENT_STATE_REVIEW.md)

## 1. Goal

FreshservicePSU will be a PSU-first module in which an ordinary script contains only the operation it needs:

```powershell
Add-FreshServiceTicketNote `
    -TicketId 12345 `
    -Body 'Investigating the issue' `
    -Private
```

The script does not connect, construct a context, select an environment, name a secret, or handle transport behavior.

The module will:

- Use the authenticated PSU user's Freshservice API key when a personal mapping exists.
- Use a dedicated system-account key only for configured fallback or noninteractive work.
- Isolate prod and dev configuration through separate PSU environments.
- Centralize authentication, URI construction, serialization, HTTP, pagination, retries, errors, and safe logging.
- Support unit and contract testing without PSU, secrets, or a live tenant.

### Intended workloads

The near-term need is a defined set of PSU workloads, not a general-purpose API wrapper:

| Workload | Commands |
| --- | --- |
| Create a ticket | `New-FreshServiceTicket` |
| Add a note | `Add-FreshServiceTicketNote` |
| Close a ticket | `Set-FreshServiceTicket` — **kept separate from the note** and composed in a script, per §10's one-command-one-operation rule |
| Reports and visualizations | `Get-FreshServiceTicket`, `Search-FreshServiceTicket`, and the focused reporting reads below |
| Ticket history | `Get-FreshServiceTicketActivity` |
| Asset pages and automations | `Get-FreshServiceAsset`, `Set-FreshServiceAsset`, `Get-FreshServiceAssetType`, `Get-FreshServiceAssetAssignmentHistory` |

Supporting reads for form values and core report dimensions: `Get-FreshServiceTicketField`, `Get-FreshServiceAgentGroup`, `Get-FreshServiceDepartment`, `Get-FreshServiceLocation`, and `Get-FreshServiceAgent`. These are the cache-eligible reference reads in §11 and need no per-user attribution.

Additional reporting reads are `Get-FreshServiceRequester`, `Get-FreshServiceRequestedItem`, `Get-FreshServiceTask`, `Get-FreshServiceRequestApproval`, `Search-FreshServiceApproval`, `Get-FreshServiceSLAPolicy`, and `Get-FreshServiceBusinessHour`. They support requester, catalog fulfillment, task backlog, approval aging, and policy-configuration reports. They are not implicitly cacheable: the request pipeline applies the caller's authorization and the endpoint-specific pagination and record limits.

Ticket creation still supplies the requester by email rather than requiring a requester lookup. Agent and requester reads are retained for reporting, not as prerequisites for creating a ticket.

**The module does not own report storage.** It returns bounded typed API results and rate-limit metadata to consuming scripts. A PSU script may call the API live or implement scheduled extraction, checkpoints, and persistence, but those storage and retention choices remain outside FreshservicePSU. Consumers should stagger bulk work and preserve rate-limit capacity for interactive calls.

## 2. Non-goals

- Backward compatibility with the current connection-profile system or command shapes.
- Windows PowerShell 5.1 or the `Desktop` PowerShell edition.
- Automatic console fallback or ambient module connection state.
- Freshservice for MSPs, Freshservice for Business Teams, or API v1.
- Caller-selected tenant, stage, base URI, identity, or secret reference.
- **Broad API coverage.** The new major supports the commands the intended workloads require and removes the rest. It is a PSU integration for defined operations, not a general-purpose Freshservice wrapper. Adding a command is a small, documented task against the command-authoring pattern established in Phase 5 Slice A when a workload needs one.

The redesign is published as a new major version. `Connect-FreshService`, saved profiles, automatic aliases, global variables, and import-time connection behavior are removed.

## 3. Settled decisions

| Area | Decision |
| --- | --- |
| Primary host | PSU is the only host supported by public commands. |
| Runtime | PowerShell 7.6 LTS and `CompatiblePSEditions = @('Core')`. |
| PSU authentication | Support SAML and OIDC through one normalized PSU identity contract. SAML is currently deployed; OIDC can be introduced without changing public commands or credential-map keys. |
| Access control | PSU controls access to consuming apps, APIs, and scripts; Freshservice enforces the resolved API key's permissions. The module defines no PSU roles. |
| Human attribution | Select the API key mapped to the authenticated PSU user. |
| Fallback | Use the stage's dedicated system account only when policy allows it or execution is noninteractive. |
| Environment | Prod and dev are separate PSU environments with separately managed secrets. |
| Configuration and secrets | The PSU variable `FreshservicePSUConfig` supplies versioned non-secret configuration; PSU's built-in vault supplies secrets through a provider-neutral adapter. |
| Workspace | The tenant has one workspace; workspace selection is not part of configuration, context, or public commands. |
| Trust boundary | Public commands fail closed when trusted PSU invocation data is absent or invalid. |
| Context lifetime | Resolve per operation; never cache contexts or credentials in module, runspace, PSU cache, output, or disk. |
| HTTP design | Every endpoint uses one focused private request pipeline. |
| Rate limits | Seed the limiter with documented Enterprise limits and update runtime state from response headers; limiter scope is stage, tenant, and endpoint class. |
| Reference cache | Eligible reference data uses PSU cache for 15 minutes with stage/tenant isolation, invalidation, and bypass. |
| Output contract | Typed properties are compatibility contracts; format views are presentation only. |
| Exports | The manifest is the single source of exported functions and aliases. |
| Command scope | Export exactly the accepted 22 commands; CSAT is conditional and time entries are excluded. |
| Asset scope | Asset commands are reusable PSU capabilities and do not implement external synchronization or destructive asset operations. |
| Consumer boundary | Scripts and apps own UI, schedules, reporting persistence, checkpoints, refresh, retention, and data-access policy. |
| Audit boundary | The module emits safe structured audit information but does not select a logging sink or retention policy. |
| Release | The redesign starts at `1.0.0` with a new module GUID and is distributed as a versioned GitHub release artifact with a SHA-256 checksum; it is not published to the PowerShell Gallery. |
| Migration | New endpoints use the new pipeline immediately; existing families migrate incrementally. |

## 4. Runtime contract

Target PowerShell 7.6 LTS on every supported PSU execution environment. The manifest must declare:

```powershell
PowerShellVersion    = '7.6'
CompatiblePSEditions = @('Core')
```

The conversion removes Windows PowerShell compatibility branches, `UseBasicParsing`, `System.Web`, and process-global `ServicePointManager` changes. HTTP exceptions, headers, multipart bodies, JSON, URI encoding, dates, and UTF-8 behavior are tested against PowerShell 7.6 and its .NET runtime.

This gives the module one HTTP and exception model, current security servicing, native PSU hosting, and cross-platform execution. The tradeoff is intentional: Windows PowerShell consumers and full-framework-only dependencies are unsupported.

## 5. Trusted execution flow

```text
PSU App / API / Automation / Schedule
                  |
                  v
         Public Freshservice command
                  |
                  v
          PSU host adapter
          identity + stage
                  |
                  v
        Credential resolution
          personal | system
                  |
                  v
       Ephemeral execution context
                  |
                  v
          Request pipeline
       URI -> body -> HTTP -> output
                  |
                  v
            Freshservice API
```

The PSU adapter is explicit and mandatory. The module does not detect a host and does not fall back to a less-trusted adapter. Tests invoke private services with explicit test contexts instead of creating public ambient state.

## 6. Identity and access boundary

The PSU adapter normalizes SAML and OIDC into one internal identity contract:

```text
Freshservice.ExecutionPrincipal
  PrincipalId        trusted-provider + tenant + immutable-object-id
  UserPrincipalName  readable UPN or username
  ExecutionType      Interactive or System
  AuthenticationType SAML, OIDC, or System
```

Provider-specific claims never escape the adapter or influence public command
syntax. For Microsoft Entra ID, the initial mappings are:

| Purpose | SAML | OIDC |
| --- | --- | --- |
| Immutable object ID | `http://schemas.microsoft.com/identity/claims/objectidentifier` | `oid` |
| Tenant | `http://schemas.microsoft.com/identity/claims/tenantid` or trusted issuer mapping | `tid` or trusted issuer mapping |
| Readable username | `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name` | `preferred_username`, then `upn` |

The canonical credential-map key is `entra:<tenant-id>:<object-id>`. This makes
the same Entra user resolve to the same personal Freshservice secret whether
PSU authenticated that session with SAML or OIDC. Other identity providers use
an equivalent trusted provider/issuer namespace plus their stable subject.

The adapter accepts only configured authentication types and trusted issuers,
requires exactly one immutable identity and one readable username, and rejects
missing or conflicting values. It never uses email alone as a credential-map
key and never accepts identity, issuer, or authentication type from ordinary
command parameters. Because claims may be renamed by host middleware,
claim candidates are trusted PSU configuration rather than constants scattered
through command code.

The trusted identity determines which API key represents an interactive action.
The module does not decide whether a user may run a consuming PSU resource: PSU
app, API, script, and token permissions own that decision. Freshservice then
enforces the permissions attached to the selected personal or system API key.
Credential mapping is identity selection, not an additional authorization layer.

If PSU cannot expose a trustworthy initiator for an Automation job, either route the request through an authenticated PSU API/App boundary or classify the job as noninteractive and use the system account.

Any PSU roles or group policies used to protect a consuming app, API, or script
remain consumer configuration and are outside the module contract. App tokens,
schedules, and other explicitly noninteractive executions use the configured
system identity after PSU has allowed the resource to run.

## 7. Environment and credential configuration

Use separate PSU environments:

| PSU environment | Stage | Host | System credential |
| --- | --- | --- | --- |
| `FreshService-Prod` | `Prod` | Production tenant | Dedicated prod system account |
| `FreshService-Dev` | `Dev` | Sandbox or development tenant | Dedicated dev system account |

The assigned PSU environment selects the stage. Public command parameters cannot override the stage, tenant, base URI, or secret reference.

The PSU environment supplies non-secret configuration through the trusted PSU
variable `FreshservicePSUConfig`. Secrets remain in PSU's built-in vault;
configuration contains only their names. The configuration contract starts at
schema version `1.0`:

```powershell
@{
    SchemaVersion        = '1.0'
    Stage               = 'Prod'
    Tenant              = 'acme'
    BaseUri             = 'https://acme.freshservice.com/api/v2/'
    DefaultSecret       = 'FreshService.System.Prod'
    AllowSystemFallback = $true
    Authentication = @{
        AllowedTypes   = @('SAML', 'OIDC')
        TrustedTenants = @('<entra-tenant-id>')
        TrustedIssuers = @(
            'https://sts.windows.net/<entra-tenant-id>/'
            'https://login.microsoftonline.com/<entra-tenant-id>/v2.0'
        )
    }
    Users = @{
        'entra:<entra-tenant-id>:<object-id-alice>' = 'FreshService.Alice.Prod'
    }
}
```

The allowed top-level properties are `SchemaVersion`, `Stage`, `Tenant`,
`BaseUri`, `DefaultSecret`, `AllowSystemFallback`, `Authentication`, and `Users`.
`Authentication` accepts only `AllowedTypes`, `TrustedTenants`, and
`TrustedIssuers`. Unknown properties, unsupported schema versions, duplicate or
case-colliding user keys, non-HTTPS base URIs, and base URIs outside
`/api/v2/` fail validation.

**Accepted validation rules.** Four rules are fixed here because a validator is
the wrong place for them to be discovered:

- **`BaseUri` is bound to the tenant.** Its host must equal
  `<Tenant>.freshservice.com` and its path must be exactly `/api/v2/`. An
  exact-path check alone still accepts `https://attacker.example.com/api/v2/`,
  which would direct every authenticated request at another host. The tenant
  is on the standard Freshservice domain; a vanity domain would require an
  explicit new configuration property rather than a looser check.
- **`BaseUri` carries no userinfo, query, or fragment.** Userinfo smuggles
  credentials into a URI, and a query or fragment silently alters every
  request built from the base.
- **`AllowedTypes` is a closed set of `SAML` and `OIDC`.** These are the
  mechanisms the module implements (see the rollout section below). A typo or
  an unimplemented mechanism fails at configuration validation rather than
  reading as valid configuration that grants nothing.
- **Property names must be unique case-insensitively at every level**, not
  only in `Users`. A case-sensitive dictionary can hold both `Stage` and
  `stage`; only one is ever read, so the configuration is ambiguous and fails.

The adapter reads and validates the variable at the
start of every public operation; configuration is not cached, so an
administrator's stage, tenant, issuer, or secret-reference correction takes
effect without recycling a runspace. Configuration integrity is
security-sensitive because it selects the tenant and secret. Missing,
ambiguous, unreadable, or invalid configuration fails closed; the module never
substitutes a default tenant.

### SAML-to-OIDC compatibility rollout

1. Keep the current SAML provider enabled and capture sanitized normalized
   identity results for two users.
2. Configure OIDC in PSU with the same Entra tenant and preserve the consuming
   apps', APIs', and scripts' existing PSU access policies.
3. Use PSU's claim-information view to confirm `oid`, tenant/issuer, and readable
   username without recording tokens.
4. In development PSU, verify that SAML and OIDC produce the same canonical
   `PrincipalId` for each test user and therefore select the same vault entry.
5. Test interactive, app-token, schedule, unknown-identity, and reused-runspace cases.
6. Enable OIDC for normal use only after these identity and access tests
   pass. Removing SAML is an independent deployment choice and is not required
   for module compatibility.

## 8. Credential selection

`Resolve-FsuCredential` applies this policy after validating the trusted PSU execution boundary:

| Condition | Result |
| --- | --- |
| Authenticated caller with a working personal mapping | Use the personal credential. |
| Authenticated caller without a mapping | Use the system credential only when fallback is allowed. |
| Personal mapping exists but its secret cannot be loaded | Fail; do not fall back. |
| Personal key is rejected by Freshservice | Fail with safe credential identification; do not fall back. |
| Scheduled or explicitly noninteractive execution | Use the system credential. |
| Unknown or unauthenticated interactive caller | Deny. |

The requirement this policy exists to serve, stated by the module owner on 2026-08-12: **an action is attributed to the person who ran it, unless it came from an API call or a schedule, in which case it is attributed to a named system identity.** An interactive offboarding script run by an administrator is authored by that administrator; a Workflow Automator call into a PSU API is authored by a system account. The table above implements exactly that, so the per-user credential design is load-bearing rather than speculative.

Per-user keys are the committed mechanism, and a `user_id` field never impersonates the caller or substitutes for credential selection. This is a **decision subject to one open gate** — see §15 item 8: the sandbox spike may show that `user_id` genuinely controls note authorship, which would satisfy the same requirement with one system key and no registry.

When fallback is used, Freshservice attributes the action to the system account. PSU audit records must retain the initiating identity, and human-visible content may include an attribution footer.

## 9. Execution context

`Get-FsuExecutionContext` validates the PSU boundary and returns an immutable internal context containing:

- Stage, tenant, and base URI.
- Resolved API key.
- Credential type: `User` or `System`.
- Trusted PSU identity.
- Retry/throttling policy.
- Correlation ID.

The context is held only in a local invocation variable. It is never persisted, exported, written to PSU cache, or retained in module/runspace state.

A normal one-command script resolves one context. Bulk workloads use a purpose-built public batch operation whose private orchestration resolves once and passes the context explicitly through private calls.

## 10. Public command contract

Public commands contain only:

- Parameter and endpoint-specific validation.
- Path, query, and payload mapping.
- `ShouldProcess` behavior for mutations.
- The explicit response contract.

They do not read secrets, construct authentication headers, use ambient connection state, call raw HTTP cmdlets, implement retries/pagination, or infer a response envelope from its first property.

Commands that multiplex unrelated endpoints should be split. The ticket family should expose focused commands such as:

```text
Get-FreshServiceTicket
Search-FreshServiceTicket
Get-FreshServiceTicketField
Get-FreshServiceTicketActivity
Get-FreshServiceTicketCsatResponse
Add-FreshServiceTicketNote
```

Each migrated command declares `OutputType`, applies a stable `PSTypeName`, and extracts its response property explicitly. List commands stream pages as they arrive and enforce a documented record cap.

### Consolidation

The target surface does not preserve multipurpose legacy commands. Each public
command owns one operation, endpoint family, and response shape. Local payload
builders are private validation helpers rather than exported `New-*` commands,
and a `204 No Content` operation never fabricates success output before the
response is known.

The command-by-command legacy evidence, replacements, and removals belong in
[COMMAND_PRUNE_LIST.md](COMMAND_PRUNE_LIST.md). That record controls migration
notes; this architecture controls only the target rules.

### Naming

The name states the operation, one command performs one operation, and the noun
matches the resource returned by the endpoint. A switch may filter the same
resource, but it never selects an unrelated endpoint or output shape. Property
updates use `Set-*`; named transitions use an approved action verb. Destructive
operations never hide behind a mode switch and require a separate command with
appropriate `ConfirmImpact`. `Get-FreshServiceBusinessHour` retains the singular
noun required by PowerShell convention.

### Private helpers use a reserved prefix

The `FreshService` noun prefix is reserved for exported commands. **Private helpers are `Verb-Fsu<Thing>` and are never exported.** Any identifier containing `FreshService` is therefore public by definition — in source, in tests, in tab completion, and in a stack trace — so the supported surface is readable without consulting the manifest.

| Private helper | Purpose |
| --- | --- |
| `Get-FsuExecutionContext` | Validate the PSU boundary and build the per-operation context (§9). |
| `Resolve-FsuCredential` | Apply the credential-selection policy (§8). |
| `Invoke-FsuRequest` / `Invoke-FsuPagedRequest` | Transport and pagination (§11). |
| `New-FsuUri`, `ConvertTo-FsuRequestBody`, `ConvertFrom-FsuResponse`, `New-FsuErrorRecord` | Request construction, serialization, and error normalization. |

Two reasons this is a rule rather than a preference. PSU runs many modules and dot-sourced scripts in shared sessions, so a leaked generic helper such as `New-FreshServiceUri` can shadow or be shadowed by another module's function; the `Fsu` prefix matches the module name and removes that collision class. And the context and credential helpers are exactly the ones §13 requires never to escape the module — a name that cannot be mistaken for a supported command makes an accidental export visible on sight.

`PSTypeName` values are unaffected. They remain `FreshservicePSU.<Resource>` because they are output contracts rather than commands (Q13).

### Naming applies to unimplemented endpoints too

`API_V2_COVERAGE_MATRIX.md` and `FRESHSERVICE_API_V2_ENDPOINT_COMPARISON.csv` record 24 missing and 26 partial endpoint families against 22 with legacy coverage. Those counts describe *legacy endpoint families*; they are unrelated to the 22-command target surface in `SUPPORTED_COMMANDS.md`. The naming rules are therefore mostly a rule for *new* commands, not a rename exercise, and two findings connect the two efforts.

**Mode switches corrupt the coverage review.** The comparison marks `/assets` as needing "permanent delete" added and Agents as needing "forget and conversion" verified. All three already exist — as `Remove-FreshServiceAsset -delete_forever`, `Remove-FreshServiceAgent -Forget`, and `Set-FreshServiceAgent -convert_to_requester`. A capability hidden behind a switch is invisible to anyone auditing the command list, so the surface cannot be checked against the API by name. This is an independent argument for the naming rules: once each endpoint has exactly one command, coverage becomes mechanically verifiable rather than a manual reading of parameter blocks. Phase 8 should generate the coverage matrix from the command list rather than maintaining it by hand.

**Two areas are out of scope rather than unnamed.** The tenant has one workspace and the releases family is excluded (`CLAUDE.md`), so the comparison's P1 rows for `/tickets/{id}/move_workspace`, the equivalent move endpoints on problems and changes, workspace CRUD, and the entire `/releases` family are **Skip**, not gaps. This removes four planned `Move-FreshService*` commands, five `Release` commands, and `Release` from twelve parent-type `ValidateSet` declarations across the note, task, and time-entry commands.

New families adopt the rules directly:

| Gap | Naming |
| --- | --- |
| Ticket and change approvals, approval groups, global approvals (P1) | `Get`/`New`/`Set`/`Remove-FreshServiceApproval -Type Ticket\|Change`, `Send-FreshServiceApprovalReminder`, and `*-FreshServiceApprovalGroup`. `-Type` is admissible here because ticket and change approvals are parallel endpoints returning the same shape. This replaces the current `RequestApproval` naming split across two folders. |
| Solution category and folder restore, permanent delete (P2) | Extend the combined `Restore-*` `ValidateSet`; permanent delete becomes `Clear-FreshServiceSolutionCategory` / `Clear-FreshServiceSolutionFolder`. |
| Attachment deletion on tickets, conversations, projects, contracts (P1/P2) | `Remove-FreshServiceTicketAttachment` and siblings — one command per parent resource, never a switch on the parent's `Remove-*`. |
| Major-incident promote/demote (P2) | Action verbs, not `Set-` switches. |
| Asset, purchase-order, software-user, contract move operations (P2) | `Move-FreshService*` if these move between something other than workspaces; if they are workspace moves, they are out of scope. Confirm per endpoint before implementing. |
| Alerts, CABs, on-call schedules, shared fields (P2) | New families; each documented endpoint gets one command, and no sub-resource read is folded into its parent's `Get-`. |
| Physical subtypes, devices, cloud resources (P3) | **Skip** — out of scope per `CLAUDE.md`. Core asset management is unaffected. |
| Journeys, employee onboarding and offboarding (P2) | **Skip** — the tenant has not implemented these features. The existing onboarding commands are removed rather than migrated. |
| Time entries, attachments (mixed) | **Skip** — not required by any intended workload (§1). |

The `Decision (Add/Skip)` column in the comparison records Phase 0's explicit Add/Skip/Conditional call for every row. This section is independent of that column: it fixes the name each gap will take **if** it is ever added, so the decision and the naming are not relitigated together.

## 11. Request pipeline

Replace `Invoke-FreshworksRestMethod` with focused private helpers:

| Helper | Responsibility |
| --- | --- |
| `Invoke-FsuRequest` | Per-request authentication, HTTP execution, retry policy, safe logging, and response metadata. |
| `Invoke-FsuPagedRequest` | Link-header pagination, streaming, result limits, and page ceilings. |
| `New-FsuUri` | Escaped path segments and encoded query parameters. |
| `ConvertTo-FsuRequestBody` | JSON, dates, nulls, depth, and multipart bodies (serialization conventions below). |
| `ConvertFrom-FsuResponse` | Explicit response-envelope extraction and output typing. |
| `New-FsuErrorRecord` | Normalized, safe, machine-parseable errors. |

Every endpoint uses this pipeline. Transport uses a **module-scoped `HttpClient` over a `SocketsHttpHandler` with a bounded `PooledConnectionLifetime`**, so connections are reused as the vendor guidance asks and no handler is constructed per call. Authentication is attached to each request and never placed on the client or its default headers: the shared client outlives any single operation's context (§9) and must never carry one caller's authorization into another caller's request.

### Retry policy

- Honor `Retry-After` in seconds or HTTP-date form.
- Use bounded exponential backoff with jitter when no server delay is supplied.
- Cap attempts, individual delay, and total retry duration.
- Retry safe/idempotent operations by default.
- Replay non-idempotent operations only under an explicitly approved policy.
- Treat a confirmed `429` separately from an ambiguous network failure.
- Never manufacture a synthetic success or pagination response.
- Throw a normalized terminating error after exhaustion.

Interactive PSU calls use a short budget below the browser/API timeout. Background jobs may use a longer bounded policy. A low remaining budget can warn, reserve capacity, or refuse new bulk work; it must not cause an arbitrary sleep on an interactive path.

**Accepted budgets.** An interactive operation has a **20-second total-time budget**, measured from the first send through the last retry. A retry is attempted only when the next backoff wait *plus* an estimated request duration fits inside the remaining budget; otherwise the operation fails immediately with the normalized error rather than consuming the budget in a wait it cannot afford. Noninteractive callers may configure a longer bounded budget, defaulting to **120 seconds**. Both values are configuration, not public command parameters. If development PSU proves the host terminates interactive requests sooner than 20 seconds, the configured interactive budget is lowered to sit below the observed limit; the retry rule is unchanged by that measurement.

**Correlation.** Every operation carries a correlation ID through its audit events and normalized errors. It is **not** sent to Freshservice: the module adds no custom correlation request header, because no documented Freshservice v2 header accepts one. A contract test asserts that no such header appears on outbound requests. A future documented vendor requirement reopens this.

### Pagination and embedding

- Set `per_page` explicitly and validate it from 1 through 100.
- Follow the `link` response header; its absence terminates paging.
- Refuse page numbers above 500 and direct callers to narrow the query.
- Enforce result limits before fetching another page.
- Expose endpoint-specific `include` values as validated sets.
- Keep embedding opt-in because it consumes additional API credits.

List and search commands stream records as pages complete. If a later page
fails, the command throws a terminating `FreshservicePSU.PartialResults` error
whose safe metadata includes the correlation ID, pages completed, records
emitted, and whether more data was known to exist. It never includes a
continuation token or response body. Already-emitted records cannot be recalled;
consumers must discard or explicitly reconcile them when the command terminates.
Examples therefore collect streaming results inside `try`/`catch` and never
persist a run as complete until the command returns successfully.

Every request has a cancellation source linked to its total-time budget and to
host or pipeline cancellation when that signal is available. Cancellation
disposes the response and request content, performs no retry, emits a safe
failure audit event, and throws a terminating cancellation error. Cache and
limiter reservations are released or reconciled in `finally` paths. Contract
tests cover cancellation before send, during response, between pages, and while
waiting to retry.

Embedding cost is documented per embedded resource: **+1 credit** on an endpoint returning a single object, **+2 credits** on one returning a collection. Two consequences follow. `include` is the main reason a call's cost varies, so cost is read from `X-RateLimit-Used-CurrentRequest` rather than estimated. And embedding competes with the reference-data cache below: cache non-volatile lookups, embed volatile per-record detail, and never do both for the same field.

A response fetched with `include` carries extra properties. The `PSTypeName` stays the same with or without it, the embedded property is extracted by name like any other, and documented output marks such properties as conditional.

### Reference-data cache

Freshservice asks clients to cache non-volatile data to avoid repeat calls, naming the agent name-to-ID mapping as an example. This is a **different mechanism** from execution-context handling in §9, which prohibits caching contexts and credentials. Both rules hold simultaneously, so the boundary is stated explicitly:

- Cacheable data is **non-secret and non-permission-filtered only** — agent, group, department, location, asset-type, and ticket-field lookups. Never cache anything whose content depends on which credential fetched it, and never cache a resolved context, credential, or key.
- Every cache key includes stage and tenant. One tenant's or stage's lookup table must never serve another.
- Entries use a 15-minute default TTL. A private/admin invalidation mechanism clears entries without adding a business command to the public export surface.
- The cache is opt-out per call for callers needing authoritative data.
- Reference data uses PSU cache so it can be shared across host runspaces. Stage and tenant scoping are mandatory. Execution contexts and credentials never enter this cache.

### Rate limits

Freshservice v2 documentation specifies minute-level, account-wide limits and endpoint-specific sublimits. The Enterprise limits below are the module's configured baseline. Response headers provide live remaining-credit and request-cost telemetry, while `Retry-After` controls recovery from a `429`.

The limiter is scoped by stage, tenant, and endpoint class—not by API key. Read total, remaining, current-request cost, `Retry-After`, and API-version headers from responses. Credential selection affects attribution, not throughput.

The limiter uses a private provider contract with atomic reserve, reconcile,
release, and expiry operations. Production uses a PSU-accessible shared provider
so every runspace and host process for one environment observes the same state;
an in-memory provider exists only for deterministic unit tests. Keys include a
schema version, stage, tenant, endpoint class, and minute window. Provider
unavailability fails closed before sending any request. The module never
silently replaces a failed shared provider with a process-local production
limiter.

Production uses one PSU node. The provider stores non-secret limiter state in
PSU's server-level cache and serializes each read/reserve/reconcile/write
transaction with one OS-named mutex scoped to the limiter schema and PSU node.
The cache is not persisted to PSU's database. Phase 1 verifies that the named
mutex is shared by the node's actual worker processes on the production
operating system. Tests exercise competing reservations across runspaces and
processes, stale-window expiry, provider failure, abandoned-lock recovery, and
service restart. Multi-node deployment is unsupported; moving to multiple nodes
requires reopening this decision and selecting a distributed atomic provider.

Documented per-minute limits:

| Action | Starter | Growth | Pro | Enterprise |
| --- | --- | --- | --- | --- |
| Overall limit | 100 | 200 | 400 | 500 |
| List All Tickets | 40 | 70 | 120 | 140 |
| View Ticket | 50 | 80 | 140 | 160 |
| Create Ticket | 50 | 80 | 140 | 160 |
| Update Ticket | 50 | 80 | 140 | 160 |
| List All Assets | 40 | 70 | 120 | 140 |
| Update Asset | 50 | 80 | 140 | 160 |
| List All Agents | 40 | 70 | 120 | 140 |
| List All Requesters | 40 | 70 | 120 | 140 |

The 140-against-500 gap is why the limiter is keyed by endpoint class: a paginated ticket query can be rejected while `X-RateLimit-Remaining` still reports most of the account budget, because that header carries one number and cannot indicate which sublimit is being approached. A percentage of the overall limit is therefore a heuristic that reduces `429` frequency, never a guarantee against it, and the `429` path must stay correct on its own.

### Errors

Normalize Freshservice HTTP status, `code`, `field`, and message into stable PowerShell error categories and `FullyQualifiedErrorId` values. Preserve actionable validation details without including secrets, authorization headers, or sensitive request bodies.

The `code` values are a documented, closed set, which makes this a mapping problem rather than a judgment call: `missing_field`, `invalid_value`, `duplicate_value`, `datatype_mismatch`, `invalid_field`, `invalid_json`, `invalid_credentials`, `access_denied`, `require_feature`, `account_suspended`, `ssl_required`, `readonly_field`, `password_lockout`, `password_expired`, `no_content_required`, `inaccessible_field`, `incompatible_field`, `unsupported_authentication_type`, `access_token_expired`, `access_token_invalid`.

Statuses: 400 validation, 401 authentication failure, 403 access denied or feature not enabled, 404 not found, 405 method not allowed, 406 unsupported `Accept`, 409 conflicting state, 415 unsupported `Content-Type`, 429 rate limit, 500 server error.

Four groupings carry design weight:

- **Credential and tenant state** — `invalid_credentials`, `access_token_expired`, `account_suspended`, `password_expired`, `password_lockout`. These fail without retry and must stay individually distinguishable, because §13's invariant that a configured personal credential never falls back silently depends on recognizing exactly this set.
- **`require_feature`** is the tenant feature-flag case named in `CLAUDE.md`. It gets a distinct, self-explaining error rather than a generic 403, since it is the expected failure when a flag-gated capability is absent from the target tenant.
- **`readonly_field`, `inaccessible_field`, `incompatible_field`** are three different causes presenting as one rejected update. Keep them distinct.
- **405, 406, 415** indicate a defect in this module's own request construction rather than in caller input. Surface them as such and cover them in contract tests.

`field` is preserved in the error record; it is what makes a 400 actionable and is exactly what the legacy transport discards (CURRENT_STATE_REVIEW F12).

### Vendor change policy

Freshservice may add attributes **at any time with no notice**; removals and behavior changes carry 60 days' advance notice, with an explicit carve-out for legal, performance, and security reasons.

The additive half is the documented justification for §10's rule against inferring a response envelope from its first property — a new envelope attribute is a change that can ship any day and would silently change which data a command returns. The 60-day half sets the planning horizon for breaking changes; contract tests are what turn that notice period into a signal, since nothing in the module watches the changelog.

One caution on the reference page: its Policies section still says v2 scope is "limited to only tickets and conversations" while the same page documents roughly fifty resource families, and its rate-limit header table retains hourly wording contradicted by the section above it. Treat the page as authoritative for shapes and semantics, and the tenant as authoritative for limits and availability.

### Serialization conventions

`ConvertTo-FsuRequestBody` and `ConvertFrom-FsuResponse` (table above) are the only
places that serialize or deserialize. Phase 4's contract tests assert these rules
directly, so they are fixed here rather than left to implementation judgment:

| Concern | Convention |
| --- | --- |
| JSON depth | `ConvertTo-Json -Depth 10`. Request bodies are shallow; 10 is a guard against silent truncation, not a modeled limit. |
| Text encoding | UTF-8 without a byte-order mark on every request and response body, and on every file this pipeline writes. |
| Date/time on the wire | ISO 8601 UTC (`yyyy-MM-ddTHH:mm:ssZ`), matching Freshservice's documented format. Values are converted to UTC before serialization; the pipeline never sends a local offset. |
| Null handling | A parameter left unbound is omitted from the request body. A parameter explicitly set to `$null` is sent as JSON `null`. Commands distinguish the two with `$PSBoundParameters`, never with `-eq $null` on the value. Response `null` is passed through unchanged; it is never coerced to an empty string or `$false`. |
| Enum handling | Public parameters use PowerShell `ValidateSet` (§10) over string literals matching Freshservice's documented values verbatim, including case. The pipeline sends the validated string as-is; it never remaps to a numeric or internal code. |
| `SecureString` | Never serialized. Credential material is converted to plain text only inside the request-construction call that attaches an `Authorization` header (§6/§8), immediately before the request is sent, and is not retained in a variable, log, cache, or error record afterward. |
| Multipart bodies | Out of scope today because attachments are out of scope (`CLAUDE.md`). If a future accepted workload needs multipart, `ConvertTo-FsuRequestBody` grows a distinct multipart branch alongside the JSON branch — it is not the JSON path's default, and the JSON conventions above still govern any JSON part within a multipart body. |

These conventions apply uniformly across the pipeline (§11) and do not vary by
resource; a resource-specific exception would itself be a contract-test failure.

## 12. Module layout and loading

```text
FreshservicePSU/
  FreshservicePSU.psd1
  FreshservicePSU.psm1
  Public/
    Tickets/
    Assets/
    ...
  Private/
    Configuration/
    Execution/
    Hosts/PowerShellUniversal/
    Http/
    Serialization/
    Errors/
tests/
  Unit/
  Contract/
  Integration/
  Architecture/
```

The manifest is the single source of public functions and aliases. It exports no variables, uses no dynamic aliases, and explicitly empties unused export fields. The module loader imports private helpers before public commands in deterministic order.

An offline `tests/Architecture` check enforces the naming boundary in §10, so an accidental export fails CI rather than reaching a PSU session:

- every function defined under `Private/` matches `^[A-Z][a-zA-Z]*-Fsu[A-Z]`, case-sensitively — the verb may be multiword, as in `ConvertTo-FsuRequestBody`;
- no function under `Private/` contains `FreshService`;
- no function under `Public/` contains `Fsu`;
- while implementation is incomplete, `FunctionsToExport` is an ordered subset of `SUPPORTED_COMMANDS.md` containing only commands that meet their phase exit criteria; Phase 6 and every release require the exact complete list;
- `AliasesToExport`, `VariablesToExport`, and `CmdletsToExport` are empty.

Import performs no network calls, secret resolution, profile reads, automatic connections, or user-facing output.

## 13. Security invariants

- PSU controls access to consuming Apps, APIs, scripts, and tokens; the module defines no roles of its own.
- Anonymous interactive execution is denied even when system fallback exists.
- Caller identity, stage, tenant, base URI, and secret references cannot come from ordinary user parameters.
- Trusted identity validation completes before secret resolution.
- Resolved contexts and keys never enter PSU cache, runspace/module state, output, disk, or logs.
- A configured personal credential failure never falls back silently.
- Prod and dev use distinct system credentials.
- Authentication is attached per request, never to shared HTTP client defaults.
- Logs omit keys, authorization values, complete request headers, and unredacted sensitive bodies.
- Audit records include correlation ID, PSU identity, stage, tenant, credential type, non-secret credential identifier, operation, resource ID, outcome, status, fallback use, and rate-limit state.

### Audit delivery

Audit events are typed `FreshservicePSU.AuditEvent` objects written only to the
PowerShell information stream with the tag `FreshservicePSU.Audit`. They never
enter the success-output pipeline. A consuming PSU script can capture the stream
with `-InformationVariable` or information-stream redirection and send it to its
chosen sink; ignoring the stream does not change command behavior. Each attempted
HTTP operation emits one terminal success, failure, cancellation, or
uncertain-outcome event. `-WhatIf` may emit a preview event but never a success
event. Event construction and redaction happen before `Write-Information`, and
audit-delivery failure cannot turn an unsuccessful Freshservice operation into
success. Contract tests assert the type, tag, one-terminal-event rule, and
separation from command output.

## 14. Test boundaries

- **Unit:** identity normalization, credential-selection policy, URI/body conversion, retry decisions, redaction, errors, context isolation, and caching of non-secret reference data.
- **Contract:** exact HTTP method/URI/headers/body, explicit response extraction, pagination, result caps, retry/error behavior, `ShouldProcess`, output typing, and rate-limit metadata.
- **PSU integration:** trusted identities on each PSU surface, personal/system selection, prod/dev isolation, and pooled-runspace isolation.
- **Live Freshservice:** opt-in tests using disposable dev records for authorship, fallback, revoked credentials, pagination headers, and representative multipart/error behavior.

## 15. Deployment decisions

Closed decisions:

- The tenant has one workspace. Workspace selection exists nowhere in the public surface or execution context.
- Schedules, background automations, and Workflow Automator calls use a named system identity. Interactive operations use the authenticated caller's selected credential.
- A shared stage/tenant/endpoint limiter is authoritative. PSU job-concurrency controls supplement it.
- Production has one PSU node. Its limiter combines server-level PSU cache with an OS-named cross-process mutex and does not persist limiter state to a database; multi-node deployment requires a new distributed-provider decision.
- Typed object properties are the compatibility contract; format views are presentation only.
- The module returns bounded typed results; consuming scripts choose live or scheduled execution and own any report persistence.
- Eligible reference data uses PSU cache with a 15-minute TTL, private/admin invalidation, and per-call bypass.
- Releases start at `1.0.0`, replace the inherited GUID, and are attached to a tagged GitHub release as a versioned module archive plus SHA-256 checksum. PSU receives the unpacked versioned module directory from that artifact. PowerShell Gallery publication is out of scope unless explicitly approved later.
- Release validation covers a clean install, an upgrade from the preceding FreshservicePSU release, explicit-version import, reused-runspace replacement behavior, and rollback to the preceding artifact. Authenticode signing is not required unless the deployment execution policy requires it.

Unresolved environment, integration, and command-contract questions are maintained only in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md). That registry records how each answer is obtained and the evidence required; accepted decisions move into the authoritative documents.

## 16. Definition of done

- Ordinary PSU scripts call only operation commands.
- Personal and system attribution follows the selection policy and is integration-tested.
- The PSU boundary fails closed and pooled runspaces cannot leak caller state.
- Prod/dev configuration and credentials are isolated.
- PowerShell 7.6 is the only supported runtime.
- Every endpoint uses the shared pipeline and normalized error contract.
- Public commands contain no connection, credential, HTTP, retry, or pagination implementation.
- List commands stream typed records under bounded result and page limits.
- Module import has no external side effects.
- Unit and contract tests need no external credentials; credentialed tests are isolated and opt-in.
- No key or authorization value appears in logs or output.
- Legacy findings marked S1/S2 in the current-state review are absent by test.

## References

- [Freshservice API v2](https://api.freshservice.com/v2/)
- [Freshservice v2 rate-limit scope](https://support.freshservice.com/support/solutions/articles/50000000293-what-is-the-rate-limit-for-apis-across-all-plans-)
- [PowerShell support lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6)
- [PowerShell 5.1 and 7 differences](https://learn.microsoft.com/powershell/scripting/whats-new/differences-from-windows-powershell?view=powershell-7.6)
- [PowerShell Universal SAML2](https://docs.powershelluniversal.com/v4-beta/config/security/saml2)
- [PowerShell Universal OpenID Connect](https://docs.powershelluniversal.com/security/enterprise-security/openid-connect)
- [PowerShell Universal server-level cache](https://docs.powershelluniversal.com/platform/cache)
- [Microsoft Entra SAML claims](https://learn.microsoft.com/en-us/entra/identity-platform/single-sign-on-saml-protocol)

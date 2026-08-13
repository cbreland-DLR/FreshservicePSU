# FreshservicePSU open questions

- **Status:** Active decision and evidence queue
- **Updated:** 2026-08-12

This file contains unresolved items only. Questions are grouped by who can
answer them and how the answer is obtained. Once resolved, the result moves to
the appropriate architecture, implementation-plan, README, or command-reference
section and is removed here. Never record API keys, tokens, secret values, or
unsanitized claims in this repository.

## Blocking map

An open question blocks only the work listed below. It does not prevent work on
the clean module skeleton, offline CI, shared serialization and error helpers,
or unrelated commands.

| ID | Blocking level | Work actually blocked |
| --- | --- | --- |
| **Q1** | Core contract, current SAML portion only | Phase 3 trusted PSU adapter and credential selection cannot be completed until the current SAML identity source is known. Pending OIDC evidence blocks only declaring OIDC deployment-ready. |
| **Q2** | Core contract, current SAML portion only | Phase 3 canonical `PrincipalId`, personal-secret lookup, and audit identity cannot be completed until current SAML claims normalize correctly. Pending OIDC comparison blocks only OIDC deployment readiness. |
| **Q3** | Release validation | Phase 8 supported runtime/OS matrix and final package validation. It does not block implementation on the declared PowerShell 7.6 and PSU 2026.x targets. |
| **Q4** | Pipeline feature | Phase 4 interactive total-time and retry-budget contract. URI, HTTP, serialization, errors, pagination, and noninteractive pipeline work may proceed. |
| **Q6** | Pipeline feature | Phase 4 outbound-header contract tests only. Accepting the audit-only default closes it without a sandbox dependency. |
| **Q7** | One mutation and attribution validation | Final `Add-FreshServiceTicketNote` authorship behavior and the decision whether personal API keys remain necessary. Other commands and the default personal-key implementation may proceed. |
| **Q8** | One read command | `Search-FreshServiceApproval` implementation and export. Other approval and reporting commands are not blocked. |
| **Q9** | One read command | `Get-FreshServiceAssetAssignmentHistory` implementation and export. Other asset commands are not blocked. |
| **Q10** | Two mutation commands | Public parameters and request contracts for `New-FreshServiceTicket` and `Set-FreshServiceTicket`. |
| **Q11** | One mutation command | Public parameters and request contract for `Set-FreshServiceAsset`. |
| **Q12** | One read command | Parameter sets and URI contracts for `Get-FreshServiceAsset`. |
| **Q13** | Per-command completion | Stable typed-output completion for each command. It is answered incrementally and does not block starting a command slice. |
| **Q14** | One read command | Embed parameters and API-credit contract for `Get-FreshServiceTicket`. Basic ticket retrieval can be developed first. |
| **Q15** | Phase 4 deployment validation | Production is settled as one PSU node. Only the proof that server-level cache plus the OS-named mutex coordinates all worker processes remains open; other pipeline work may proceed. |

Conditional future-scope items block nothing unless the project owner promotes
one into the active command set.

## 1. Project-owner decisions

These define what the public commands allow. The project owner can answer them
without running an integration test.

| ID | Decision needed | Recommended answer | How to answer and record it |
| --- | --- | --- | --- |
| Q10 | Which ticket fields may scripts create and update? | Expose common Freshservice ticket fields required by consuming scripts and validated `CustomFields`; do not reproduce the entire legacy parameter list. | List the fields scripts must set when creating a ticket, then list the fields they may change later. Mark every other field unsupported. Move the accepted lists into `SUPPORTED_COMMANDS.md` and command contract tests. |
| Q11 | Which asset properties may `Set-FreshServiceAsset` update? | Permit owner, department, location, state, assignment date, ordinary descriptive properties, and allowlisted type-specific values. Exclude asset-type changes, deletion, restoration, and arbitrary properties. | Accept the recommendation or edit the allowed list. During implementation, map each friendly parameter to its exact Freshservice field and add request-body tests proving that omitted fields are never sent. |

## 2. Environment facts

These are not design choices. A PSU administrator records facts from the PSU
test instance and identity-provider configuration. Sanitized evidence is enough.

| ID | Fact needed | How to answer | Completion evidence |
| --- | --- | --- | --- |
| Q1 | Which trusted PSU values provide identity to Apps, authenticated APIs, automation jobs, schedules, and app-token calls under SAML and OIDC? | Create one temporary diagnostic invocation for each supported PSU surface and authentication type. Record the names and data types of the available identity, claims-principal, and issuer/tenant values; include only sanitized examples. Test two interactive users, an unknown user, a schedule/system execution, an app token, and a reused runspace. SAML evidence can be collected now; repeat the matrix when OIDC is configured. | A matrix naming the trusted identity source for each surface and authentication type, including missing-value behavior. OIDC may remain Pending until configured without blocking SAML implementation. |
| Q2 | Which SAML and OIDC claims normalize to the same immutable credential-map key and readable UPN? | For current Entra SAML, confirm object identifier, tenant or trusted issuer, and name/UPN. When OIDC is configured, confirm `oid`, `tid` or trusted issuer, and `preferred_username` or `upn`. For two users, compare sanitized normalized results and verify both protocols produce `entra:<tenant-id>:<object-id>`. | The exact claim names for each provider plus sanitized evidence that both normalize to the same `PrincipalId` and readable username. Do not record assertions, ID tokens, or access tokens. |
| Q15 | Does server-level PSU cache plus an OS-named mutex coordinate every worker process that runs module code? Production is already confirmed as one PSU node. | Record the development topology and the worker-process count on both environments. In one environment, reserve limiter capacity from two concurrent worker processes and confirm that both observe the same counter and that the named mutex serializes them. Repeat after a PSU restart to confirm the cache is non-persistent as assumed. | Worker-process topology plus sanitized evidence that competing reservations are serialized on the single production node. A failed cross-process result reopens the provider design rather than shipping an uncoordinated limiter. |
| Q3 | Which exact PSU 2026.x release, operating system, and PowerShell 7.6 patch run in development and production? | Read the PSU release from the admin console. In each PSU environment run `$PSVersionTable.PSVersion.ToString()` and `[System.Runtime.InteropServices.RuntimeInformation]::OSDescription`. | A development and production row containing PSU version, PowerShell version, and OS. PSU variables and the built-in secret vault are already settled. |

## 3. Engineering defaults

These can be answered by accepting the recommendation. Tests then verify the
implementation; the project owner does not need to discover the answer.

| ID | Engineering question | Recommended answer | How to answer and verify it |
| --- | --- | --- | --- |
| Q4 | What total-time budget applies to an interactive PSU operation? | Start with a 20-second total budget. Retry only when the next wait and request can finish inside the remaining budget. Allow consuming noninteractive scripts to use a bounded configurable budget. | Accept the default, then run controlled 5-, 10-, 20-, and 30-second test operations in development PSU. Lower the configured budget if the host terminates requests sooner. Record the final value in `ARCHITECTURE.md`. |
| Q6 | Should the module send a correlation header to Freshservice? | Keep correlation IDs in module audit and error data only; do not send an undocumented custom header. | Accept the default and add a contract test proving no custom correlation header is sent. A future documented requirement can reopen this decision. |
| Q12 | Which asset lookup forms does `Get-FreshServiceAsset` support? | Display ID, asset tag, serial number, and a bounded validated filter. Do not add endpoint-selecting modes. | Accept the list, document separate parameter sets, and add URI tests for each lookup plus ambiguous, invalid, and over-limit inputs. |
| Q13 | What output does each command guarantee? | Assign `PSTypeName` values under `FreshservicePSU.<Resource>` and guarantee identifiers, display labels, relationship IDs, state/status, and relevant timestamps. Treat additional API attributes as non-contractual. | Define an output-property table for each command while implementing its slice. Contract tests compare the stable property names, types, and `PSTypeName`; extra vendor fields may pass through without becoming guarantees. |
| Q14 | Which ticket embeds are exposed? | Keep embeds opt-in. Initially allow requester, statistics, and conversations. Use dedicated commands for requested items, tasks, approvals, and activity. | Accept the list, document the API-credit cost, and add contract tests for no embeds, each permitted embed, combined permitted embeds, and rejected values. |

## 4. Freshservice integration verification

These answers come from the Freshservice sandbox. They determine whether a
proposed implementation is valid in the target tenant; an unavailable feature
must produce a distinct error or be removed from scope rather than look like an
empty result.

| ID | Behavior to verify | How to test safely | Answer format |
| --- | --- | --- | --- |
| Q7 | Does `user_id` change ticket-note authorship, which privilege is required, and does an unauthorized value fail? | On a disposable sandbox ticket, add notes using the system key with no `user_id`, a valid agent ID, and an unauthorized agent ID. Repeat with privileged and ordinary credentials. Compare returned authorship and the Freshservice audit trail, then remove or close the test record according to sandbox policy. | Record whether authorship changed, the required privilege, and whether unauthorized impersonation failed explicitly. Keep personal API keys unless the result safely satisfies the attribution requirement. |
| Q8 | Is global approval search available, authorized, filtered, and paginated as documented? | Call `GET /approvals` in the sandbox with the documented required filters. Cover a matching result, no result, unauthorized caller, invalid filter, and more than one page when test data permits. Capture sanitized status, envelope property names, and pagination metadata. | Record Available or Unavailable, required filters, response envelope, pagination method, and permission needed. Remove `Search-FreshServiceApproval` from scope if the tenant cannot support it. |
| Q9 | Is asset assignment history available and shaped as expected? | Call `GET /assets/{display_id}/assignment-history` for a reassigned asset, never-assigned asset, missing asset, and unauthorized caller. Capture sanitized status, envelope property names, and pagination metadata. | Record Available or Unavailable, identifier type, response envelope, pagination method, and permission needed. Remove `Get-FreshServiceAssetAssignmentHistory` from scope if unavailable. |

## 5. Conditional future scope

These are not active questions or implementation work. A consuming-script use
case must be named before one is promoted into the decision queue.

| Capability | Promotion trigger | How to answer after promotion |
| --- | --- | --- |
| Ticket CSAT response | A consumer requires a CSAT report and the tenant uses Freshservice surveys. | Name the consuming script, required fields, endpoint entitlement, and expected output contract. |
| Standalone ticket conversations | A consumer needs independent retrieval rather than the ticket embed. | Explain why the embed is insufficient and define paging and output requirements. |
| Catalog item and category reads | A consuming script needs service-catalog choices. | Name the script and exact fields required for choices and validation. |
| Canned responses | A consuming script inserts approved response templates. | Define search, selection, permission, and output requirements. |
| Solution article search | A consuming script provides knowledge suggestions. | Define its query, ranking, permissions, and bounded result requirements. |
| Custom-object reads | A supported ticket or asset field requires custom-object-backed choices. | Name the dependent field and define the smallest read-only command contract that satisfies it. |

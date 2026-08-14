# FreshservicePSU open questions

- **Status:** Active decision and evidence queue
- **Updated:** 2026-08-13

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
| **Q7** | One mutation and attribution validation | Final `Add-FreshServiceTicketNote` authorship behavior and the decision whether personal API keys remain necessary. Other commands and the default personal-key implementation may proceed. |
| **Q8** | One read command | `Search-FreshServiceApproval` implementation and export. Other approval and reporting commands are not blocked. |
| **Q9** | One read command | `Get-FreshServiceAssetAssignmentHistory` implementation and export. Other asset commands are not blocked. |
| **Q13** | Per-command completion | Stable typed-output completion for each command. It is answered incrementally and does not block starting a command slice. |
| **Q15** | Phase 4 deployment validation | Production is settled as one PSU node. Only the proof that server-level cache plus the OS-named mutex coordinates all worker processes remains open; other pipeline work may proceed. |

Conditional future-scope items block nothing unless the project owner promotes
one into the active command set.

## 1. Environment facts

These are not design choices. A PSU administrator records facts from the PSU
test instance and identity-provider configuration. Sanitized evidence is enough.

| ID | Fact needed | How to answer | Completion evidence |
| --- | --- | --- | --- |
| Q1 | Which trusted PSU values provide identity to Apps, authenticated APIs, automation jobs, schedules, and app-token calls under SAML and OIDC? | Create one temporary diagnostic invocation for each supported PSU surface and authentication type. Record the names and data types of the available identity, claims-principal, and issuer/tenant values; include only sanitized examples. Test two interactive users, an unknown user, a schedule/system execution, an app token, and a reused runspace. SAML evidence can be collected now; repeat the matrix when OIDC is configured. Use `tools/Get-PsuIdentityEvidence.ps1` with the run matrix in `tools/README.md`. | A matrix naming the trusted identity source for each surface and authentication type, including missing-value behavior. OIDC may remain Pending until configured without blocking SAML implementation. |
| Q2 | Which SAML and OIDC claims normalize to the same immutable credential-map key and readable UPN? | For current Entra SAML, confirm object identifier, tenant or trusted issuer, and name/UPN. When OIDC is configured, confirm `oid`, `tid` or trusted issuer, and `preferred_username` or `upn`. For two users, compare sanitized normalized results and verify both protocols produce `entra:<tenant-id>:<object-id>`. Use `tools/Get-PsuIdentityEvidence.ps1` with the run matrix in `tools/README.md`. | The exact claim names for each provider plus sanitized evidence that both normalize to the same `PrincipalId` and readable username. Do not record assertions, ID tokens, or access tokens. |
| Q15 | Does server-level PSU cache plus an OS-named mutex coordinate every worker process that runs module code? Production is already confirmed as one PSU node. | Record the development topology and the worker-process count on both environments. In one environment, reserve limiter capacity from two concurrent worker processes and confirm that both observe the same counter and that the named mutex serializes them. Repeat after a PSU restart to confirm the cache is non-persistent as assumed. Use `tools/Get-PsuIdentityEvidence.ps1` with the run matrix in `tools/README.md`. | Worker-process topology plus sanitized evidence that competing reservations are serialized on the single production node. A failed cross-process result reopens the provider design rather than shipping an uncoordinated limiter. |
| Q3 | Which exact PSU 2026.x release, operating system, and PowerShell 7.6 patch run in development and production? | Read the PSU release from the admin console. In each PSU environment run `$PSVersionTable.PSVersion.ToString()` and `[System.Runtime.InteropServices.RuntimeInformation]::OSDescription`. Use `tools/Get-PsuIdentityEvidence.ps1` with the run matrix in `tools/README.md`. | A development and production row containing PSU version, PowerShell version, and OS. PSU variables and the built-in secret vault are already settled. |

### Vendor-documentation findings for Q1 and Q2 (2026-08-13)

Collected from the Devolutions PowerShell Universal documentation, which now
hosts the former `docs.powershelluniversal.com` content. These narrow the probe;
none of them substitute for evidence from the actual instance, because the docs
do not state per-surface behavior for every case the questions ask about.

Established:

- **There is no `$PSUIdentity` or `$UAIdentity`.** Both names circulate in
  forum posts and older material and neither appears in the current variable
  reference. Any design written against them would not run.
- **The identity surface differs per execution surface**, which is the core of
  Q1:

  | Surface | Documented identity values |
  | --- | --- |
  | API | `$Identity` (string), `$ClaimsPrincipal` (ClaimsPrincipal) |
  | App | `$User` (string, `$null` when authentication is disabled), `$Roles` (string[]), `$ClaimsPrincipal` |
  | Script / Schedule | `$UAJob` (job object carrying `.Identity.Name`), `$Roles`; **no `$ClaimsPrincipal` is documented** |

- **Scheduled and script executions therefore cannot perform claim-based
  normalization.** Without a claims principal there is no `oid`/`tid` to build
  `entra:<tenant-id>:<object-id>` from, only a name string. This supports the
  existing design in ARCHITECTURE.md §8: noninteractive execution uses the
  system credential rather than a personal mapping.
- **PSU requires the SAML name claim
  `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name`** as the user
  identity; other attributes are available for role evaluation only if the IdP
  is configured to send them. Entra role mapping uses
  `http://schemas.microsoft.com/ws/2008/06/identity/claims/role`.
- **System app tokens are documented as "not tied directly to a user's
  identity"** and are distinct from user app tokens.

Still unknown, and what the instance probe must answer:

- Whether Entra's SAML assertion actually carries object-identifier and
  tenant-identifier claims in this tenant, and under exactly which claim type
  URIs. Q2's `entra:<tenant-id>:<object-id>` key depends on this and cannot be
  assumed from the required name claim alone.
- How `$Identity` and `$ClaimsPrincipal` are populated for app-token calls, for
  user tokens versus system tokens. The documentation does not say.
- What each surface yields for an unknown or unauthenticated caller, which is
  the fail-closed path.
- Whether a reused runspace retains a previous caller's values.

Sources, all retrieved 2026-08-13:

- <https://docs.devolutions.net/powershell-universal/platform/variables>
- <https://docs.devolutions.net/powershell-universal/security/security>
- <https://docs.devolutions.net/powershell-universal/security/app-tokens>
- <https://docs.devolutions.net/powershell-universal/security/enterprise-security/saml2>

Treat these as current-version documentation, not as evidence about the
deployed instance. The older `docs.powershelluniversal.com` URLs now redirect
here, and search results still surface pre-migration pages and forum posts —
that is where the nonexistent `$PSUIdentity` and `$UAIdentity` names come from.

## 2. Engineering defaults

These can be answered by accepting the recommendation. Tests then verify the
implementation; the project owner does not need to discover the answer.

| ID | Engineering question | Recommended answer | How to answer and verify it |
| --- | --- | --- | --- |
| Q13 | What output does each command guarantee? | Assign `PSTypeName` values under `FreshservicePSU.<Resource>` and guarantee identifiers, display labels, relationship IDs, state/status, and relevant timestamps. Treat additional API attributes as non-contractual. | Define an output-property table for each command while implementing its slice. Contract tests compare the stable property names, types, and `PSTypeName`; extra vendor fields may pass through without becoming guarantees. |

## 3. Freshservice integration verification

These answers come from the Freshservice sandbox. They determine whether a
proposed implementation is valid in the target tenant; an unavailable feature
must produce a distinct error or be removed from scope rather than look like an
empty result.

| ID | Behavior to verify | How to test safely | Answer format |
| --- | --- | --- | --- |
| Q7 | Does `user_id` change ticket-note authorship, which privilege is required, and does an unauthorized value fail? | On a disposable sandbox ticket, add notes using the system key with no `user_id`, a valid agent ID, and an unauthorized agent ID. Repeat with privileged and ordinary credentials. Compare returned authorship and the Freshservice audit trail, then remove or close the test record according to sandbox policy. | Record whether authorship changed, the required privilege, and whether unauthorized impersonation failed explicitly. Keep personal API keys unless the result safely satisfies the attribution requirement. |
| Q8 | Is global approval search available, authorized, filtered, and paginated as documented? | Call `GET /approvals` in the sandbox with the documented required filters. Cover a matching result, no result, unauthorized caller, invalid filter, and more than one page when test data permits. Capture sanitized status, envelope property names, and pagination metadata. | Record Available or Unavailable, required filters, response envelope, pagination method, and permission needed. Remove `Search-FreshServiceApproval` from scope if the tenant cannot support it. |
| Q9 | Is asset assignment history available and shaped as expected? | Call `GET /assets/{display_id}/assignment-history` for a reassigned asset, never-assigned asset, missing asset, and unauthorized caller. Capture sanitized status, envelope property names, and pagination metadata. | Record Available or Unavailable, identifier type, response envelope, pagination method, and permission needed. Remove `Get-FreshServiceAssetAssignmentHistory` from scope if unavailable. |

## 4. Conditional future scope

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

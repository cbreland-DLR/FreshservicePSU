# Phase 1 evidence tooling

`Get-PsuIdentityEvidence.ps1` collects the facts that open questions Q1, Q2, Q3,
and Q15 need from a live PowerShell Universal instance. Those questions block
the Phase 3 identity adapter, credential selection, `Invoke-FsuRequest`, the
production rate limiter, and the Phase 8 release matrix.

This directory is operator tooling. It is not part of the module, is not
exported, and is checked separately with `./build.ps1 -Task Tools`.

## Before running it

Read the script. It is one file and the sanitizing helpers are at the top.

- **Claim and identity values are never written to the report.** Each claim is
  recorded as its type URI, issuer, value kind, value length, and an
  8-character salted fingerprint. The default salt is regenerated per run.
  For the controlled User A/User B and later SAML/OIDC comparisons, supply the
  same temporary `SecureString` through `-ComparisonSecret`; it is never
  written to the report. Delete that temporary secret after the comparison.
- **It is read-only unless you pass `-RunSharedStateTest`.** That switch is the
  only thing that writes: it takes an OS-named mutex and uses one PSU cache
  entry under an `FsuEvidence.` key. Use the documented `Cleanup` role after a
  normal concurrency probe; `RestartCheck` cleans up its own restart marker.
- Review the JSON before sharing it.

## Running it

Run once per surface, labelling each run:

```powershell
./Get-PsuIdentityEvidence.ps1 -SurfaceLabel 'API-SAML-UserA'
```

To satisfy the questions, collect these runs:

| Run | Surface | Why |
| --- | --- | --- |
| `API-SAML-UserA` | Authenticated API endpoint | Q1 API row, Q2 claim types |
| `API-SAML-UserB` | Same endpoint, second user, with the same temporary comparison secret | Q2: confirm two users produce different fingerprints |
| `App-SAML-UserA` | App page | Q1 App row |
| `Schedule-System` | Scheduled script | Q1 script/schedule row; expected to have no `$ClaimsPrincipal` |
| `AppToken-User` | API called with a user app token | Q1 app-token row, undocumented |
| `AppToken-System` | API called with a system app token | Same, for the non-user case |
| `Unauthenticated` | Endpoint reached without credentials | Fail-closed behavior |
| `Limiter-ProcessA` / `Limiter-ProcessB` | Two worker processes using the same shared-state probe ID | Q15 cache and mutex coordination |
| `Limiter-RestartSeed` / `Limiter-RestartCheck` | One run before and one after a PSU restart | Q15 cache persistence |

Deploy the same file three ways: as the body of an authenticated API endpoint,
as an App page script, and as a scheduled script. Each run reports which
surface it detected, so a mislabelled run is visible.

Only runs that need cross-report identity comparison should share a temporary
comparison secret. Create a value of at least 16 characters as a
`SecureString`, provide the same value to those runs, and remove it afterward:

```powershell
$comparisonSecret = Read-Host 'Temporary evidence comparison secret' -AsSecureString
./Get-PsuIdentityEvidence.ps1 -SurfaceLabel 'API-SAML-UserA' `
    -ComparisonSecret $comparisonSecret
```

Without `-ComparisonSecret`, fingerprints are deliberately unlinkable between
reports. Never place the comparison secret in a command line as plaintext.

For Q15, choose one non-secret probe label and use it for every command. Start
the initializer in one worker, then start the contender in a different worker
while the initializer is holding the mutex:

```powershell
./Get-PsuIdentityEvidence.ps1 -SurfaceLabel 'Limiter-ProcessA' `
    -RunSharedStateTest -SharedStateProbeId 'q15-20260813' `
    -SharedStateRole Initializer -MutexHoldSeconds 10

./Get-PsuIdentityEvidence.ps1 -SurfaceLabel 'Limiter-ProcessB' `
    -RunSharedStateTest -SharedStateProbeId 'q15-20260813' `
    -SharedStateRole Contender -MutexHoldSeconds 10

./Get-PsuIdentityEvidence.ps1 -SurfaceLabel 'Limiter-Cleanup' `
    -RunSharedStateTest -SharedStateProbeId 'q15-20260813' `
    -SharedStateRole Cleanup
```

A successful pair has the same `ProbeHash`; Process A writes counter 1;
Process B sees the cache before acquiring the mutex, observes the initializer,
waits for the mutex, and advances the counter from 1 to 2. Both round trips
must succeed. If either worker fails, run `Cleanup` with the same probe ID.

Test restart persistence separately. Seed the marker, restart PSU, then run the
check with the same probe ID:

```powershell
./Get-PsuIdentityEvidence.ps1 -SurfaceLabel 'Limiter-RestartSeed' `
    -RunSharedStateTest -SharedStateProbeId 'q15-restart-20260813' `
    -SharedStateRole RestartSeed

# Restart PSU before this command.
./Get-PsuIdentityEvidence.ps1 -SurfaceLabel 'Limiter-RestartCheck' `
    -RunSharedStateTest -SharedStateProbeId 'q15-restart-20260813' `
    -SharedStateRole RestartCheck
```

`CachePersistedAfterRestart = false` confirms the non-persistent behavior the
provider design assumes. `RestartCheck` removes a surviving marker as well.

For Q3, any single run records the PowerShell version and OS; read the PSU
release from the admin console separately.

## What to do with the reports

Summarize them into `docs/OPEN_QUESTIONS.md` against the relevant question and
delete the raw files. Never commit a report: even sanitized, it describes the
identity configuration of a production tenant, and the repository rule in that
file is that unsanitized claims are never recorded here.

## Expected findings

Two results are predicted by the vendor documentation and are worth confirming
rather than assuming:

- A scheduled run should have `$UAJob` but no `$ClaimsPrincipal`. If so, a
  schedule cannot build `entra:<tenant-id>:<object-id>`, which supports using
  the system credential for noninteractive execution.
- `$PSUIdentity` and `$UAIdentity` should both be absent. They appear in older
  forum material and do not exist in the current variable reference; the script
  probes them so their absence is recorded rather than assumed.

A result that contradicts either one reopens the identity design, so report it
rather than working around it.

## Freshservice sandbox evidence

`Get-FreshserviceSandboxEvidence.ps1` collects sanitized Freshservice sandbox
evidence for Q7, Q8, Q9, and the correlation-header spike. It prompts for a
sandbox API key as a `SecureString` unless one is supplied, uses it only for
the request, and never writes it to the JSON report. The report records status,
response-header names, and JSON property names/types only; it contains no
response values, identifiers, query values, or header values.

Run the read-only scenarios once for each relevant credential and label every
run distinctly:

```powershell
./Get-FreshserviceSandboxEvidence.ps1 -Scenario ApprovalSearch `
    -BaseUri 'https://example.freshservice.com/api/v2/' `
    -ApprovalQuery 'filter=%7B%22...%22%7D' -SurfaceLabel 'Q8-Authorized'

./Get-FreshserviceSandboxEvidence.ps1 -Scenario AssetAssignmentHistory `
    -BaseUri 'https://example.freshservice.com/api/v2/' `
    -AssetDisplayId 123 -SurfaceLabel 'Q9-ReassignedAsset'

./Get-FreshserviceSandboxEvidence.ps1 -Scenario CorrelationHeader `
    -BaseUri 'https://example.freshservice.com/api/v2/' `
    -SurfaceLabel 'CorrelationHeader'
```

For Q7, use a **disposable sandbox ticket only**. Note creation is blocked
unless both its ID and the explicit acknowledgement are supplied. Run it with
no `-UserId`, a valid agent `-UserId`, and an unauthorized one; use
`-ExpectedAuthorId` when the expected note author is known. Compare the
sanitized result with the Freshservice audit trail, then close or remove the
test ticket under the sandbox policy.

```powershell
./Get-FreshserviceSandboxEvidence.ps1 -Scenario TicketNote `
    -BaseUri 'https://example.freshservice.com/api/v2/' -TicketId 123 `
    -UserId 456 -ExpectedAuthorId 456 -AcknowledgeWrite `
    -SurfaceLabel 'Q7-ValidUserId'
```

This is operator tooling, not module code. Review and summarize the report in
`OPEN_QUESTIONS.md`, then delete it; never commit raw reports.

### Freshservice run checklist

Use disposable sandbox records and collect every applicable row:

| Question | Runs |
| --- | --- |
| Q7 | Privileged system key: no `user_id`, valid agent, unauthorized agent. Repeat all three with the ordinary credential. Compare each result with the Freshservice audit trail. |
| Q8 | Matching filter, no-result filter, unauthorized credential, invalid filter, and a multi-page result when the sandbox has enough data. |
| Q9 | Reassigned asset, never-assigned asset, missing asset, and unauthorized credential. |
| Correlation | One authorized read with `CorrelationHeader`; record acceptance and whether Freshservice echoes the value in a response header. |

The tool reports property paths and types through nested envelopes, paging
header names and link relations, expected-author comparison, and correlation
acceptance/echo status. It never records the associated values.

## Generate a reviewable summary

After reviewing the JSON files, convert them into a temporary Markdown summary:

```powershell
./ConvertFrom-FsuEvidenceReport.ps1 `
    -Path @('/tmp/psu-evidence-one.json', '/tmp/freshservice-evidence-two.json')
```

The converter accepts only the known sanitized report schemas and fails on an
unexpected top-level field. It omits fingerprints, process IDs, tenant and
endpoint identifiers, query and response values, and header values. It writes
observations with a `Pending review` conclusion; it never edits
`OPEN_QUESTIONS.md` or closes a question automatically.

Delete the JSON reports and generated Markdown after the maintainer has moved
the approved conclusions into the authoritative documents.

## Validate operator tooling

The operator tools have a separate offline gate with mocked PSU cache and HTTP
behavior. It makes no network calls and creates no Freshservice records:

```powershell
./build.ps1 -Task Tools
```

Before committing a tooling change, run the complete repository checks:

```powershell
./build.ps1 -Task Validate,Tools
git diff --check
```

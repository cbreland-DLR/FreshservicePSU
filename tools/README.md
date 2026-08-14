# Phase 1 evidence tooling

`Get-PsuIdentityEvidence.ps1` collects the facts that open questions Q1, Q2, Q3,
and Q15 need from a live PowerShell Universal instance. Those questions block
the Phase 3 identity adapter, credential selection, `Invoke-FsuRequest`, the
production rate limiter, and the Phase 8 release matrix.

This directory is operator tooling. It is not part of the module, is not
exported, and is not covered by `build.ps1`.

## Before running it

Read the script. It is one file and the sanitizing helpers are at the top.

- **Claim and identity values are never written to the report.** Each claim is
  recorded as its type URI, issuer, value kind, value length, and an
  8-character salted fingerprint. The salt is regenerated per run, so
  fingerprints let you compare two users within one report and mean nothing
  outside it.
- **It is read-only unless you pass `-RunSharedStateTest`.** That switch is the
  only thing that writes: it takes an OS-named mutex and round-trips one PSU
  cache entry under an `FsuEvidence.` key, then removes it.
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
| `API-SAML-UserB` | Same endpoint, second user | Q2: confirm two users produce different fingerprints |
| `App-SAML-UserA` | App page | Q1 App row |
| `Schedule-System` | Scheduled script | Q1 script/schedule row; expected to have no `$ClaimsPrincipal` |
| `AppToken-User` | API called with a user app token | Q1 app-token row, undocumented |
| `AppToken-System` | API called with a system app token | Same, for the non-user case |
| `Unauthenticated` | Endpoint reached without credentials | Fail-closed behavior |
| `Limiter-ProcessA` / `Limiter-ProcessB` | Two worker processes, concurrently, with `-RunSharedStateTest` | Q15 |

Deploy the same file three ways: as the body of an authenticated API endpoint,
as an App page script, and as a scheduled script. Each run reports which
surface it detected, so a mislabelled run is visible.

For Q15, start the two limiter runs at the same time. The evidence is whether
both processes observe the same cache value and whether the named mutex
serializes them. Repeat after a PSU restart to confirm the cache is
non-persistent, which the provider design assumes.

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

# FreshservicePSU setup for PowerShell Universal

- **Status:** Accepted deployment contract; commands are not yet implemented
- **Target:** PowerShell Universal 2026.x on PowerShell 7.6

This guide describes how an administrator will install and configure the
completed FreshservicePSU module. The current development branch still contains
inherited code; do not deploy it as the target module.

## 1. Install a release

FreshservicePSU releases are versioned GitHub release artifacts rather than
PowerShell Gallery packages. Download the module archive and checksum from the
same release, verify the SHA-256 value, and extract it into a versioned module
directory visible to the PSU execution environment:

```text
<module-path>/FreshservicePSU/1.0.0/
  FreshservicePSU.psd1
  FreshservicePSU.psm1
  Public/
  Private/
```

Import an explicit version during validation:

```powershell
Import-Module FreshservicePSU -RequiredVersion 1.0.0 -Force
Get-Module FreshservicePSU | Select-Object Name, Version, Path
```

The exact PSU module path is deployment configuration, not a module contract.
Use the module path assigned to the applicable PSU environment and confirm the
loaded path before enabling consuming scripts.

## 2. Create separate PSU environments

Use `FreshService-Dev` for the sandbox tenant and `FreshService-Prod` for the
production tenant. Each environment receives its own configuration variable,
system secret, personal-secret mappings, and module version. Production is one
PSU node. Do not share secret names or configuration objects across stages.

## 3. Create vault secrets

Store every Freshservice API key in PSU's built-in vault. Create:

- one dedicated system-account key per stage; and
- one personal key per mapped user and stage when personal attribution is used.

The configuration below contains secret names only. Never put API-key values in
Git, PSU variables, examples, logs, screenshots, or test fixtures. Freshservice
permissions attached to each key determine which endpoints the caller can use.

## 4. Create `FreshservicePSUConfig`

Create this non-secret PSU variable separately in each environment:

```powershell
@{
    SchemaVersion        = '1.0'
    Stage                = 'Prod'
    Tenant               = 'acme'
    BaseUri              = 'https://acme.freshservice.com/api/v2/'
    DefaultSecret        = 'FreshService.System.Prod'
    AllowSystemFallback  = $true
    Authentication = @{
        AllowedTypes   = @('SAML', 'OIDC')
        TrustedTenants = @('<entra-tenant-id>')
        TrustedIssuers = @(
            'https://sts.windows.net/<entra-tenant-id>/'
            'https://login.microsoftonline.com/<entra-tenant-id>/v2.0'
        )
    }
    Users = @{
        'entra:<entra-tenant-id>:<object-id>' = 'FreshService.User.Prod'
    }
}
```

Use `Stage = 'Dev'`, the sandbox base URI, and dev-only secret names in the dev
environment. Unknown properties, unsupported schema versions, unsafe base URIs,
and duplicate identity mappings fail closed.

## 5. Configure identity

The module supports current SAML and planned OIDC authentication through the
same canonical Entra identity:

```text
entra:<tenant-id>:<object-id>
```

SAML must supply immutable object ID, tenant or trusted issuer, and readable
name/UPN. OIDC must supply `oid`, `tid` or trusted issuer, and
`preferred_username` or `upn`. Complete Q1 and Q2 in
[OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) with sanitized PSU evidence before the
identity adapter is declared ready. Never record assertions or tokens.

PSU controls who can run each consuming app, API, or script. The module defines
no PSU roles. Schedules, background jobs, and Workflow Automator calls use the
configured system identity.

## 6. Capture audit events

Commands write typed `FreshservicePSU.AuditEvent` records to the information
stream with the tag `FreshservicePSU.Audit`. Consuming scripts choose the audit
sink and retention policy. During validation, capture the stream separately
from command output:

```powershell
$records = Get-FreshServiceTicket -Id 1234 -InformationVariable auditEvents
$auditEvents | Where-Object Tags -Contains 'FreshservicePSU.Audit'
```

Audit events must not contain keys, authorization headers, response bodies, or
sensitive query values.

## 7. Smoke-test a deployment

In dev, then production, verify:

1. The intended module version and path load without import-time output or I/O.
2. An authenticated mapped user selects a personal secret.
3. An unknown interactive identity fails before secret resolution.
4. A schedule selects the named system identity.
5. Dev cannot resolve production configuration or secrets and vice versa.
6. Two worker processes observe serialized limiter reservations.
7. A bounded read returns typed output and one terminal audit event.
8. `-WhatIf` on a mutation sends no request and emits no success event.

Live checks use disposable sandbox records wherever a mutation is required.

## 8. Upgrade and rollback

Install a new version beside the current version. Validate it with
`-RequiredVersion` in a fresh runspace before changing PSU consumers. Recycle or
replace reused runspaces so they do not retain the previously imported module.
Keep the preceding checksummed artifact until the release is accepted.

To roll back, repoint consumers to the preceding explicit version, recycle the
affected runspaces, and repeat the smoke tests. Configuration schema changes are
breaking unless the release notes explicitly provide a compatible transition.

## 9. Common failures

| Symptom | Check |
| --- | --- |
| Configuration rejected before a request | Variable name, schema version, allowed properties, HTTPS `/api/v2/` URI, stage, and trusted issuer |
| Identity rejected | PSU surface exposes trusted claims; issuer and tenant are allowlisted; immutable object ID is present |
| Personal credential cannot load | Mapping value is the correct stage-specific vault name and the secret exists |
| Freshservice returns `401` or `403` | Key validity, endpoint permission, account state, and tenant feature entitlement |
| Limiter provider unavailable | Server-level PSU cache access and named-mutex behavior across worker processes |
| Partial-results error | Discard or explicitly reconcile emitted records; do not mark the report run complete |

See [ARCHITECTURE.md](ARCHITECTURE.md) for the security and runtime contracts and
[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the validation sequence.

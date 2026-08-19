# Security policy

## Reporting a vulnerability

Report suspected vulnerabilities privately through this fork's GitHub
[security advisories](https://github.com/cbreland-DLR/FreshservicePSU/security/advisories),
not as a public issue. Include enough detail to reproduce the problem; do not
include live-tenant data, tokens, or other secrets in the report.

## Secret handling

- Never commit secrets, API keys, or other credentials to this repository, in
  any form — sanitized or not.
- Never commit evidence collected from a live tenant or PSU instance,
  sanitized or not.
- Secrets are stored only in the PowerShell Universal secret vault
  (`PSUSecretStore`). Configuration variables (for example
  `FreshservicePSUConfig`) hold secret **names** only, never secret values.
- Application code resolves secrets at runtime through the vault; it never
  reads or logs a secret's value outside that resolution.

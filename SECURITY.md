# Security policy

## Supported versions

FreshservicePSU has not yet published its first supported fork release. The
development branch contains inherited code with known credential, retry, and
execution-state risks and must not be used for critical automation. After
`1.0.0`, only versions explicitly identified as supported in their GitHub
release notes receive security fixes.

## Reporting a vulnerability

Do not open a public issue containing a vulnerability, API key, authorization
header, identity token, tenant hostname, personal data, or private log. Use the
repository owner's private GitHub security-reporting channel. If private
reporting is unavailable, contact the maintainer through a private channel
listed on their GitHub profile and include only the minimum sanitized details
needed to arrange secure disclosure.

Include the affected version or commit, impact, reproduction conditions, and
whether the issue involves credential selection, identity validation, tenant
isolation, request logging, or Freshservice permissions. Do not test against
production or access data you are not authorized to access.

## Secret-handling expectations

- Freshservice API keys belong only in PSU's built-in vault.
- Configuration and source contain vault entry names, never secret values.
- SAML assertions, OIDC tokens, API keys, authorization headers, tenant data,
  and personal data must not appear in issues, fixtures, logs, or screenshots.
- Credentialed tests are opt-in and run only against authorized development
  environments and disposable records.
- A suspected key exposure requires immediate vault rotation and review of PSU
  and Freshservice audit records.

The target security invariants are documented in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

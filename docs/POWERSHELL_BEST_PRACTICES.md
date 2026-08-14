# FreshservicePSU PowerShell best practices

- **Applies to:** module code, build scripts, tests, and operator tools
- **Runtime:** PowerShell 7.6, Core edition
- **Authority:** implementation guidance derived from `ARCHITECTURE.md`; the
  architecture and supported-command reference win if this guide conflicts
  with either one

## 1. Start with the repository contract

- Read `ARCHITECTURE.md`, `SUPPORTED_COMMANDS.md`, `IMPLEMENTATION_PLAN.md`,
  and `OPEN_QUESTIONS.md` before implementing a command or shared helper.
- Do not turn an unresolved deployment or tenant fact into code. Keep work
  behind its documented Q-ID gate until evidence closes that question.
- Breaking cleanup is allowed for the next major version. Do not add legacy
  connection profiles, aliases, compatibility parameters, or Windows
  PowerShell workarounds.
- Keep public behavior, tests, help, and authoritative documentation in the
  same change.

## 2. Functions, files, and naming

- Use approved PowerShell verbs and singular nouns.
- Public command names use `FreshService` and must exist in the supported
  command reference before export.
- Private function names match `^[A-Z][a-zA-Z]*-Fsu[A-Z]`, case-sensitively.
  Private names never contain `FreshService`; public names never contain
  `Fsu`.
- Keep one primary function per `.ps1` file and name the file after it.
- Use `[CmdletBinding()]` on commands and non-trivial helpers. Mutation commands
  use `[CmdletBinding(SupportsShouldProcess)]`.
- Do not export aliases, variables, or cmdlets. Add a public function to the
  manifest only when its slice meets every exit criterion.

## 3. Parameters and validation

- Use explicit parameter types and `[Parameter(Mandatory)]` where omission has
  no valid meaning. Prefer switches over Boolean flags.
- Validate shape and range at the boundary with `ValidateSet`, `ValidateRange`,
  `ValidatePattern`, or focused validation code that returns a useful error.
- Accept pipeline input only when object-by-object pipeline use is part of the
  command contract and has tests.
- Do not expose tenant, stage, base URI, workspace, identity, authentication
  type, credential, API key, or secret-reference selection as ordinary public
  parameters. Those values come from the trusted PSU execution context.
- Avoid parameter sets that multiplex unrelated endpoints. Split unrelated
  operations into focused commands.
- A mutating command calls `ShouldProcess` before creating an HTTP request or
  success audit event. `-WhatIf` must perform neither action.

## 4. State, scope, and dependency flow

- Use `Set-StrictMode -Version Latest` in executable scripts and tests. Module
  validation already runs tests under strict mode.
- Never retain credentials or execution contexts in global, script, module,
  runspace, disk, or PSU-cache state.
- Resolve one immutable context per operation and pass it explicitly to
  private helpers.
- Keep mutable variables in the narrowest practical scope. Do not use global
  variables to pass data between functions.
- Inject clocks, random sources, transports, cache providers, and similar
  dependencies when deterministic tests require control over them.
- Be explicit about PowerShell enumeration: wrap possibly empty pipeline
  results in `@()` before using `.Count`; remember that returning `@()` emits
  no object and is received as `$null`.

## 5. Output and stream discipline

- Emit only contract objects on the success stream. Do not mix status text,
  audit events, formatted tables, or transport responses into command output.
- Give public results a stable `PSTypeName` under
  `FreshservicePSU.<Resource>` and guarantee the documented property names and
  types. Vendor fields may pass through only as explicitly non-contractual
  additions.
- Do not call `Format-Table`, `Format-List`, or `Out-Host` inside module
  functions. Formatting belongs to format views or the caller.
- Use `Write-Verbose` for opt-in diagnostics and the tagged information stream
  for `FreshservicePSU.AuditEvent` objects. Avoid `Write-Host` in maintained
  code.
- Do not use `Write-Output` merely to return an object; place the object on the
  pipeline. Use `return` for early control flow, not as a substitute for every
  output expression.
- Prevent helper-method return values such as collection `.Add()` results from
  leaking onto the success stream by assigning them to `$null` or casting to
  `[void]`.

## 6. Errors and failure behavior

- Fail closed when trusted identity, configuration, issuer, tenant, or secret
  resolution is missing, ambiguous, or invalid.
- Normalize Freshservice and transport failures through the shared error
  helpers. Use stable `ErrorCategory` and `FullyQualifiedErrorId` values.
- Catch an exception only to normalize it, add safe context, perform cleanup,
  or make an intentional retry decision. Otherwise allow it to propagate.
- Never convert an error, timeout, `429`, malformed response, or unavailable
  feature into an empty collection or synthetic success response.
- Error messages identify the failed operation without including credentials,
  authorization material, response bodies, sensitive query values, or secret
  names that reveal user mappings.
- Cleanup belongs in `finally`. Do not let cleanup failure hide the primary
  error unless the cleanup failure creates a more serious security risk.

## 7. Secrets and security

- Keep secrets in PSU's built-in vault and configuration limited to secret
  references. Do not persist or cache resolved secret values.
- Use `SecureString` at operator and secret-provider boundaries. If an API
  requires temporary plaintext, keep it in the smallest possible scope, clear
  byte buffers, zero unmanaged memory, and never emit it.
- Never log API keys, bearer/basic authorization values, assertions, ID or
  access tokens, raw claims, request/response bodies, or sensitive URL query
  values.
- Validate outbound base URIs against the configured tenant, HTTPS scheme, and
  exact `/api/v2/` path. Reject userinfo, query, fragment, and untrusted hosts.
- Do not use `Invoke-Expression`, dynamic script creation from user input,
  process-global TLS changes, or other ambient runtime mutation.
- Treat sanitized live evidence as temporary operational data: review it,
  summarize approved conclusions, and delete it. Never commit evidence reports.

## 8. HTTP, paging, retry, and rate limits

- Raw HTTP calls are allowed only under `Private/Http`. Public commands and
  other private folders use the shared request pipeline.
- Build paths and queries with `New-FsuUri`; serialize requests with
  `ConvertTo-FsuRequestBody`; parse envelopes with
  `ConvertFrom-FsuResponse`.
- Use bounded paging and record limits. Every loop has a deterministic stop
  condition and tests for empty, exact-boundary, multi-page, and cap behavior.
- Retry only when the shared policy permits the operation, status, idempotency,
  attempt count, and total-time budget. Honor `Retry-After` and never retry a
  rejected personal credential by silently switching identities.
- Reserve rate-limit capacity through the configured provider before sending.
  Production must never silently fall back to process-local limiter state.
- Keep correlation identifiers, retry metadata, and rate-limit telemetry out
  of stable success output; place approved metadata in response or audit
  contracts.

## 9. Serialization and data handling

- Use UTF-8 without BOM for generated text and JSON.
- Specify intentional JSON depth; never rely on a default depth that can
  truncate nested Freshservice payloads.
- Preserve `$null` versus omitted-property semantics defined by the command
  contract. Do not remove false, zero, or empty-string values as if they were
  null.
- Normalize timestamps to the documented representation and use invariant
  culture for wire values.
- Reject `SecureString` values in general request serialization. Credentials
  belong only in the authentication path.
- Do not infer an envelope from the first property of a response. Use the
  endpoint contract and fail on an unexpected shape.

## 10. Style and maintainability

- Use four-space indentation, same-line opening braces, and the repository
  formatter. Do not manually align assignment operators.
- Prefer full command and parameter names over aliases. Use splatting when a
  call has several parameters or conditional arguments.
- Prefer single-quoted strings when interpolation is unnecessary. Use `${name}`
  when interpolation would make a variable boundary ambiguous.
- Put `$null` on the left side of comparisons when a collection could be
  involved.
- Favor small pure helpers for mapping and decisions. Keep orchestration clear
  and linear; extract repeated or independently testable behavior.
- Comments explain security constraints, non-obvious PowerShell behavior, or
  why a decision exists. Do not narrate straightforward syntax.
- Do not suppress an analyzer rule without a narrow documented reason. Prefer
  changing the implementation first.

## 11. Testing expectations

- Unit, contract, and architecture tests run offline and require no PSU or
  Freshservice credentials. Live tests are isolated, tagged, opt-in, and use
  disposable development records.
- Test the real implementation. When adding a regression, break the production
  code, observe the test fail for the intended reason, then restore it.
- Mock at the HTTP or provider boundary, not the function under test.
- Cover success, validation failure, authorization failure, malformed response,
  empty result, paging limits, retry limits, and secret redaction as applicable.
- Every mutation has `ShouldProcess` and `-WhatIf` coverage proving no request
  and no success audit event occurs under `-WhatIf`.
- Every error, audit, diagnostic, and operator-report path has a test proving
  sensitive values are absent.
- Contract tests assert stable `PSTypeName`, property names, property types,
  request method/path/query/body, and envelope handling.

## 12. Required checks

Run the normal offline gate before every code commit:

```powershell
./build.ps1 -Task Validate
git diff --check
```

When anything under `tools/` or `tests/Tools/` changes, include the separate
operator-tool gate:

```powershell
./build.ps1 -Task Validate,Tools
git diff --check
```

Read the test totals and report skipped or unavailable checks in the pull
request. Passing syntax or import alone is not sufficient validation.

## Review checklist

- The change belongs to the accepted command surface and current phase.
- Naming and folder boundaries are correct.
- Trusted context cannot be overridden by public input.
- No credential, context, or identity survives the operation.
- Output and errors use the shared contracts and correct streams.
- HTTP, paging, retry, and rate-limit behavior use shared helpers.
- Mutation and redaction tests cover the new paths.
- Documentation, help, endpoint decisions, and exports remain aligned.
- The applicable validation gates pass.

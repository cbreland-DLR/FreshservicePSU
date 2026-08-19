# Credentialed integration tests

This lane is opt-in. Default `./build.ps1 -Task Validate` never discovers
`tests/Integration`.

Set `FRESHSERVICEPSU_INTEGRATION=1` in a trusted PSU or sandbox pipeline
before running these tests. They require a PSU execution context and
must not run against production.

The fixtures prove:

- interactive personal-key attribution
- schedule/system credential selection
- stage isolation
- reused-runspace isolation
- interactive timeout budget

They do not implement production pages, reports, or persistence.

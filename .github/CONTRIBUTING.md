# Contributing to FreshservicePSU

Thank you for helping improve this fork. Open an issue before starting a large
feature, architectural change, or new API-resource family so its scope can be
checked against the modernization plan.

## Project scope

Changes must remain within the scope defined in the repository guidance:

- Standard Freshservice only; MSP-specific surfaces are out of scope.
- Freshservice API v2 only.
- PowerShell 7.6 and PowerShell Universal are the target platform.
- Breaking changes are allowed for the next major version, but must be
  documented.

Read the [target architecture](../docs/ARCHITECTURE.md) and
[supported command reference](../docs/SUPPORTED_COMMANDS.md) before changing
shared transport, authentication, connection, or output behavior — the
architecture is the authority when documents disagree. Check
[open questions](../docs/OPEN_QUESTIONS.md) before assuming an unresolved
deployment or endpoint fact, and consult the
[command prune list](../docs/COMMAND_PRUNE_LIST.md) before restoring or
reintroducing a removed command name.

## Making a change

1. Create a branch from the current development branch.
2. Keep commits focused and avoid unrelated generated-file churn.
3. Add offline tests for new behavior. Keep PSU and live-tenant tests explicitly
   tagged and opt-in.
4. Update command help and architecture or migration documentation when public
   behavior changes.
5. Run the relevant checks and `git diff --check` before opening a pull request.

Run the offline repository checks from PowerShell 7.6:

```powershell
./build.ps1 -Task Test
./build.ps1 -Task Analyze
Invoke-Pester -Path ./tests/Documentation.Tests.ps1
```

Use `./build.ps1 -Task Validate -Bootstrap` only when you intend to install the
pinned build dependencies for the current user. Credentialed PSU and live
Freshservice tests are separate and opt-in.

When operator tooling changes, run its separate offline gate as well:

```powershell
./build.ps1 -Task Validate,Tools
```

The inherited resource suite connects to a live tenant and performs mutations.
Never run it against production. A pull request must state exactly which tests
were run and which could not be run.

## Pull requests

Open pull requests against
[cbreland-DLR/FreshservicePSU](https://github.com/cbreland-DLR/FreshservicePSU).
Describe the problem, the chosen design, user-visible or breaking changes, test
evidence, and any remaining limitations. Link the relevant issue when one
exists.

By contributing, you agree that your contribution is licensed under the
repository's [MIT License](../LICENSE).

Report vulnerabilities through the private process in
[SECURITY.md](../SECURITY.md), never through a public issue containing secrets
or tenant data.

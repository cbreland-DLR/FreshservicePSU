# FreshservicePSU modernization

The modernization documentation is split by purpose so architectural decisions, implementation sequencing, and legacy evidence can be read independently.

## Documents and authority

1. [Target architecture](ARCHITECTURE.md)

   The authoritative design: goals, non-goals, PSU trust boundary, per-user credential selection, request pipeline, security invariants, closed decisions, and definition of done.

2. [Supported command reference](SUPPORTED_COMMANDS.md)

   The authoritative 22-command public inventory and completed-product behavior.

3. [Command prune list](COMMAND_PRUNE_LIST.md)

   The authoritative classification of legacy command names as retained, replaced, or removed.

4. [Implementation plan](IMPLEMENTATION_PLAN.md)

   The execution order, dependencies, deliverables, tests, and phase exit criteria.

5. [Open questions](OPEN_QUESTIONS.md)

   The only active queue for unresolved deployment, command-contract, and operational decisions.

6. [Current-state review](CURRENT_STATE_REVIEW.md)

   Legacy security and correctness evidence. It explains why the rewrite is necessary but does not define target behavior.

7. [API v2 coverage matrix](API_V2_COVERAGE_MATRIX.md) and [endpoint decision CSV](FRESHSERVICE_API_V2_ENDPOINT_COMPARISON.csv)

   The matrix records legacy endpoint evidence; the CSV records explicit target-scope decisions.

8. [PowerShell Universal setup](PSU_SETUP.md)

   The operator-facing installation, configuration, identity, smoke-test,
   upgrade, and rollback procedure derived from the architecture.

## Reading order

- Read the architecture first when making or reviewing a design decision.
- Use the supported command reference for the public surface and behavior.
- Use the open-question registry before assuming a deployment fact or unresolved command detail.
- Use the implementation plan to choose and execute the next phase.
- Consult the prune list for command removal decisions and the current-state review only for legacy evidence.

If documents conflict, use the authority stated above and correct the lower-authority document in the same change. Generated help and the module manifest must match the supported command reference before release.

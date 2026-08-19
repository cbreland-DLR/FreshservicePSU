# FreshservicePSU consumer examples

These scripts show how a PSU app, API, or scheduled script should call
the public module. They are not production pages, reports, or
automations. They do not persist results, register schedules, or reach
into private module functions.

## Requirements

- PowerShell 7.6
- FreshservicePSU imported in the PSU execution environment
- A registered rate-limiter provider
- Trusted PSU identity and configuration (no tenant, stage, or API-key
  parameters)

Do not run the read examples from a workstation that lacks the PSU
execution context. The mutation previews use `-WhatIf` and send no
HTTP.

## Scripts

| Script | Public commands |
| --- | --- |
| `Read-ReferenceData.ps1` | Location, department, agent group, agent, requester, ticket field |
| `Read-Tickets.ps1` | Ticket get/search, activity, requested items, tasks, ticket approvals, approval search |
| `Read-Assets.ps1` | Asset type, asset, assignment history |
| `Read-Policies.ps1` | SLA policy, business hours |
| `Preview-TicketMutations.ps1` | New/Set ticket and add note (`-WhatIf`) |
| `Preview-AssetMutations.ps1` | Set/Remove asset (`-WhatIf`) |

List scripts collect a page into a buffer and emit it only after the
command completes. A `FreshservicePSU.PartialResults` error clears the
buffer so an incomplete extract is not treated as a finished report.

## PSU usage

Import the module in the environment, then run one script from a PSU
page, API, or job:

```powershell
Import-Module FreshservicePSU -RequiredVersion 0.1.6 -Force
& ./examples/Read-Tickets.ps1 -TicketId 152 -MaxRecords 20
& ./examples/Preview-TicketMutations.ps1 -TicketId 152
```

PSU controls who may run the script. Freshservice permissions on the
resolved API key control which endpoints succeed.

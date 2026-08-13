# FreshservicePSU command reference

FreshservicePSU provides 22 focused commands for ticket operations, asset management, PowerShell Universal forms, and reporting. Every command runs within the trusted PSU environment and uses the configured tenant and stage plus the Freshservice credential selected for the current identity. PSU controls access to the consuming resource; Freshservice controls endpoint permissions.

## 1. Ticket operations

| Command | Method and endpoint | PSU use | Behavior |
| --- | --- | --- | --- |
| `New-FreshServiceTicket` | `POST /tickets` | Ticket-creation forms and automations | Creates one ticket. Accepts the ticket fields exposed by the PSU form. Tenant, stage, base URI, and credentials come from trusted PSU configuration rather than public parameters. The single-workspace tenant requires no workspace selection. |
| `Set-FreshServiceTicket` | `PUT /tickets/{id}` | Update or close a ticket | Updates ordinary ticket properties, including status changes that close a ticket. Restore, deletion, workspace moves, and unrelated actions are separate from this command and are not supported. |
| `Get-FreshServiceTicket` | `GET /tickets/{id}` and bounded `GET /tickets` | Ticket detail, bounded lists, report facts, and optional embedded detail | Reads one ticket or streams a bounded ticket list. Endpoint-specific embeds may add conditional properties, including conversations. |
| `Search-FreshServiceTicket` | `GET /tickets/filter` | Filtered ticket retrieval for reports and visualizations | Executes a Freshservice ticket filter and returns ticket objects. |
| `Add-FreshServiceTicketNote` | `POST /tickets/{id}/notes` | Add a private or public ticket note | Adds one note. It does not send a reply or combine note creation with ticket closure. |
| `Get-FreshServiceTicketField` | `GET /ticket_form_fields` | Dynamic PSU forms and field-value resolution | Returns ticket-field definitions used to build forms and resolve stored field values to display labels. |
| `Get-FreshServiceTicketActivity` | `GET /tickets/{id}/activities` | Ticket history views and scheduled reporting | Returns ticket activity records using the endpoint's continuation-token pagination. |

## 2. Form and core report dimensions

| Command | Method and endpoint | PSU use | Behavior |
| --- | --- | --- | --- |
| `Get-FreshServiceAgentGroup` | `GET /groups[/{id}]` | Assignment choices and group report dimensions | Returns one group or a bounded group list. It does not perform membership writes or administrative actions. |
| `Get-FreshServiceDepartment` | `GET /departments[/{id}]` | Form choices and department report dimensions | Returns one department or a bounded department list. |
| `Get-FreshServiceLocation` | `GET /locations[/{id}]` | Form choices and location report dimensions | Returns one location or a bounded location list. |
| `Get-FreshServiceAgent` | `GET /agents[/{id}]` | Assignee labels and filters; workload and performance reports | Returns one agent or a bounded agent list. Agent fields, assignment history, conversions, and lifecycle actions are outside this command. |
| `Get-FreshServiceRequester` | `GET /requesters[/{id}]` | Requester-level reporting and report enrichment | Returns one requester or a bounded requester list. Ticket creation can accept requester email without first resolving an ID. Requester fields and lifecycle actions are outside this command. |

Ticket-field, agent, group, department, and location reference data may use the bounded stage-and-tenant-scoped cache defined by the architecture. Requester records are not implicitly cacheable and remain subject to Freshservice permissions and auditing.

## 3. Asset operations

| Command | Method and endpoint | PSU use | Behavior |
| --- | --- | --- | --- |
| `Get-FreshServiceAssetType` | `GET /asset_types[/{id}]` | Asset forms, filters, and validation | Returns one asset type or a bounded asset-type list. Asset-type fields are a different resource and are not selected through a mode switch. |
| `Get-FreshServiceAsset` | `GET /assets[/{display_id}]` | Asset pages, automations, and reporting | Returns one asset or a bounded asset list. Supports focused identifier, search, and filter forms without selecting component, request, contract, or relationship endpoints. |
| `Get-FreshServiceAssetAssignmentHistory` | `GET /assets/{display_id}/assignment-history` | Assignment audit and reporting | Returns the assignment history for one asset. The command reports a distinct feature-unavailable error when the tenant lacks this capability. |
| `Set-FreshServiceAsset` | `PUT /assets/{display_id}` | Controlled asset updates from PSU apps and automations | Updates caller-supplied ordinary asset properties. Supports `ShouldProcess` and `-WhatIf`; it does not create, delete, restore, permanently delete, move, or synchronize assets with an external system. |

## 4. Reporting resource reads

| Command | Method and endpoint | PSU use | Behavior |
| --- | --- | --- | --- |
| `Get-FreshServiceRequestedItem` | `GET /tickets/{ticket_id}/requested_items` | Catalog demand and fulfillment reports | Returns the requested items belonging to a ticket. It does not place or update a catalog request. |
| `Get-FreshServiceTask` | `GET /tickets/{ticket_id}/tasks[/{id}]` | Ticket-task backlog and fulfillment-duration reports | Returns tasks belonging to a ticket. Problem, change, release, and project tasks are outside the supported app workload. |
| `Get-FreshServiceRequestApproval` | `GET /tickets/{ticket_id}/approvals[/{id}]` | Approval aging and bottleneck reports | Returns approvals belonging to a ticket. Approval actions are not supported. |
| `Search-FreshServiceApproval` | `GET /approvals` | Cross-ticket approval queues, aging, and bottleneck reports | Returns a bounded filtered approval list. Requires `Parent Ticket` and at least one of approver, status, parent ID, or delegatee. |
| `Get-FreshServiceSLAPolicy` | `GET /sla_policies` | SLA configuration and policy reports | Returns SLA policy definitions. Ordinary SLA performance reporting uses ticket dates and statistics. |
| `Get-FreshServiceBusinessHour` | `GET /business_hours[/{id}]` | Business-hours configuration and policy reports | Returns one business-hours definition or a bounded list. Configuration writes are not supported. |

These resource reads are not automatically cached. Each request applies Freshservice endpoint permissions, pagination, record caps, typed output, and audit policy.

## 5. Per-command contract index

This table is the completed-product contract index. Exact parameter names,
validation sets, property types, permissions, and examples are added to the
generated help before a command is exported. Q10-Q14 identify the few entries
whose final field or embed lists still require an accepted answer.

| Command | Minimum public input or parameter sets | Stable output type | Special contract |
| --- | --- | --- | --- |
| `New-FreshServiceTicket` | Required requester identity, subject, description, and the accepted Q10 create fields | `FreshservicePSU.Ticket` | One non-idempotent create; `ShouldProcess`; no automatic replay after ambiguous delivery |
| `Set-FreshServiceTicket` | `TicketId` plus caller-supplied accepted Q10 update fields | `FreshservicePSU.Ticket` | Sends changed fields only; `ShouldProcess`; closing is a status update |
| `Get-FreshServiceTicket` | `TicketId`, or bounded list filters; optional accepted Q14 embeds | `FreshservicePSU.Ticket` | Streams lists; embeds are opt-in and expose documented conditional properties |
| `Search-FreshServiceTicket` | Validated Freshservice filter plus record limit | `FreshservicePSU.Ticket` | Streams bounded filter results; rejects unbounded or malformed filters |
| `Add-FreshServiceTicketNote` | `TicketId`, body, privacy, and supported notification fields | `FreshservicePSU.TicketNote` | `ShouldProcess`; authorship follows Q7; never sends a reply |
| `Get-FreshServiceTicketField` | Optional field identifier and bounded list controls | `FreshservicePSU.TicketField` | Eligible for the stage-and-tenant reference cache |
| `Get-FreshServiceTicketActivity` | `TicketId` plus record limit | `FreshservicePSU.TicketActivity` | Uses continuation-token pagination |
| `Get-FreshServiceAgentGroup` | Group ID or bounded list/filter input | `FreshservicePSU.AgentGroup` | Cacheable only when output is not permission-filtered |
| `Get-FreshServiceDepartment` | Department ID or bounded list/filter input | `FreshservicePSU.Department` | Eligible for the reference cache |
| `Get-FreshServiceLocation` | Location ID or bounded list/filter input | `FreshservicePSU.Location` | Eligible for the reference cache |
| `Get-FreshServiceAgent` | Agent ID or bounded list/filter input | `FreshservicePSU.Agent` | Eligible for the reference cache only when output is not permission-filtered |
| `Get-FreshServiceRequester` | Requester ID, email, or bounded list/filter input | `FreshservicePSU.Requester` | Not implicitly cached; subject to caller permissions |
| `Get-FreshServiceAssetType` | Asset-type ID or bounded list input | `FreshservicePSU.AssetType` | Eligible for the reference cache |
| `Get-FreshServiceAsset` | Accepted Q12 identifier or bounded filter parameter set | `FreshservicePSU.Asset` | Exact lookup or bounded results; no component or relationship modes |
| `Get-FreshServiceAssetAssignmentHistory` | Exact asset display ID plus record limit | `FreshservicePSU.AssetAssignmentHistory` | Q9 feature gate; distinct unavailable error |
| `Set-FreshServiceAsset` | Exact display ID plus accepted Q11 changed properties | `FreshservicePSU.Asset` | Sends changed fields only; `ShouldProcess`; no type change or destructive operation |
| `Get-FreshServiceRequestedItem` | Exact ticket ID plus record limit | `FreshservicePSU.RequestedItem` | Parent-scoped bounded read |
| `Get-FreshServiceTask` | Exact ticket ID and optional task ID plus record limit | `FreshservicePSU.Task` | Ticket tasks only; parent-scoped bounded read |
| `Get-FreshServiceRequestApproval` | Exact ticket ID and optional approval ID plus record limit | `FreshservicePSU.Approval` | Parent-scoped bounded read; no approval actions |
| `Search-FreshServiceApproval` | Parent Ticket plus at least one required documented Q8 filter | `FreshservicePSU.Approval` | Q8 feature gate; bounded cross-ticket search |
| `Get-FreshServiceSLAPolicy` | Bounded list controls | `FreshservicePSU.SLAPolicy` | Configuration read; distinct permission or feature errors |
| `Get-FreshServiceBusinessHour` | Business-hours ID or bounded list controls | `FreshservicePSU.BusinessHour` | Configuration read; distinct permission or feature errors |

Every stable output type guarantees its resource identifier, display label when
the resource has one, relevant relationship identifiers, state or status, and
relevant timestamps. Exact property names and .NET types are recorded beside
each command's implementation under Q13. Additional vendor attributes may pass
through without becoming compatibility guarantees.

Every generated help topic includes at least one PSU-focused example, paging or
record-limit behavior, cache behavior, conditional properties and API-credit
costs, normalized errors, required Freshservice endpoint permission or feature
gate, and mutation safety where applicable.

## 6. Contract shared by every command

Every command:

- runs through the trusted PSU execution-context and shared request pipeline;
- selects personal or configured fallback credentials without exposing or caching secrets;
- derives tenant and stage from trusted PSU configuration rather than public parameters;
- uses one operation, one resource shape, and one stable output type;
- validates identifiers, filters, includes, paging, and record limits before transport;
- normalizes errors and honors the bounded retry and rate-limit policy;
- emits safe audit records without response bodies, credentials, or sensitive query values; and
- includes command help describing conditional embedded properties and endpoint costs.

List commands stream pages as they arrive and stop at the configured record and page limits. Optional embeds remain opt-in because they consume additional Freshservice API credits.

## 7. Export rule

The module exports exactly the 22 commands in this reference and no generated aliases. Two of them are provisional until Phase 1 sandbox evidence lands: `Search-FreshServiceApproval` (`OPEN_QUESTIONS.md` Q8) and `Get-FreshServiceAssetAssignmentHistory` (Q9) are removed, reducing the count, if the tenant cannot support their endpoints. CSAT remains conditional rather than committed, and time entries remain out of scope. Other Freshservice API operations are outside the app's supported public surface.

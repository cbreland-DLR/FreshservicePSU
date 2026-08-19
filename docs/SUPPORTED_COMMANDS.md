# FreshservicePSU command reference

FreshservicePSU provides 23 focused commands for ticket operations, asset management, PowerShell Universal forms, and reporting. Every command runs within the trusted PSU environment and uses the configured tenant and stage plus the Freshservice credential selected for the current identity. PSU controls access to the consuming resource; Freshservice controls endpoint permissions.

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
| `Remove-FreshServiceAsset` | `DELETE /assets/{display_id}` | Remove an asset from authorized PSU apps and automations | Soft-deletes one asset (vendor trash). Supports `ShouldProcess` and `-WhatIf` with high confirm impact. It does not restore, permanently delete, or move the asset. |

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
generated help before a command is exported. The accepted field, lookup, and
embed lists are in §6; each command's stable output properties are finalized
with its implementation slice.

| Command | Minimum public input or parameter sets | Stable output type | Special contract |
| --- | --- | --- | --- |
| `New-FreshServiceTicket` | `-Email` or `-RequesterId`, plus `-Subject` and `-Description`; optional §6.1 fields | `FreshservicePSU.Ticket` | One non-idempotent create; `ShouldProcess`; no automatic replay after ambiguous delivery; output contract in §6.6 |
| `Set-FreshServiceTicket` | `-TicketId` plus at least one §6.1 update field | `FreshservicePSU.Ticket` | Sends changed fields only; `ShouldProcess`; closing is a status update; output contract in §6.6 |
| `Get-FreshServiceTicket` | `-TicketId`, or `-RequesterId`/`-Email`/`-UpdatedSince`/`-Filter` plus `-PerPage`/`-MaxRecords`; optional `-Include` from §6.3 | `FreshservicePSU.Ticket` | Streams lists; embeds are opt-in; output contract in §6.6 |
| `Search-FreshServiceTicket` | `-Query` plus `-PerPage`/`-MaxRecords` | `FreshservicePSU.Ticket` | `GET /tickets/filter`; rejects empty, unbounded, malformed, overlong, and `workspace_id` queries; output contract in §6.6 |
| `Add-FreshServiceTicketNote` | `-TicketId`, `-Body`, optional `-Private`/`-NotifyEmails` | `FreshservicePSU.TicketNote` | `ShouldProcess`; does not send `user_id` until Q7 evidence; never sends a reply; output contract in §6.21 |
| `Get-FreshServiceTicketField` | List, or `-Id` / `-Name` lookup after the list request | `FreshservicePSU.TicketField` | Eligible for the reference cache; output contract in §6.7 |
| `Get-FreshServiceTicketActivity` | `TicketId` plus record limit | `FreshservicePSU.TicketActivity` | Uses continuation-token pagination |
| `Get-FreshServiceAgentGroup` | `-Id`, or `-PerPage`/`-MaxRecords` | `FreshservicePSU.AgentGroup` | Cacheable only when not permission-filtered; output contract in §6.8 |
| `Get-FreshServiceDepartment` | `-Id`, or `-Name` plus `-PerPage`/`-MaxRecords` | `FreshservicePSU.Department` | Eligible for the reference cache; output contract in §6.9 |
| `Get-FreshServiceLocation` | `-Id`, or optional `-Name` plus `-PerPage`/`-MaxRecords` | `FreshservicePSU.Location` | Eligible for the reference cache; output contract in §6.5 |
| `Get-FreshServiceAgent` | `-Id`, or `-Email`/`-Active`/`-State` plus `-PerPage`/`-MaxRecords` | `FreshservicePSU.Agent` | Cacheable only when not permission-filtered; output contract in §6.10 |
| `Get-FreshServiceRequester` | `-Id`, or `-Email` plus `-PerPage`/`-MaxRecords` | `FreshservicePSU.Requester` | Not implicitly cached; subject to caller permissions; output contract in §6.11 |
| `Get-FreshServiceAssetType` | `-Id`, or `-PerPage`/`-MaxRecords` | `FreshservicePSU.AssetType` | Eligible for the reference cache; output contract in §6.13 |
| `Get-FreshServiceAsset` | `-DisplayId`, `-AssetTag`, `-SerialNumber`, or `-Filter` plus `-PerPage`/`-MaxRecords` | `FreshservicePSU.Asset` | Exact lookup or bounded results; no component or relationship modes; output contract in §6.12 |
| `Get-FreshServiceAssetAssignmentHistory` | `-DisplayId` plus `-PerPage`/`-MaxRecords` | `FreshservicePSU.AssetAssignmentHistory` | Q9 feature gate; `FreshservicePSU.Asset.AssignmentHistoryUnavailable` on require_feature/405; output contract in §6.14 |
| `Set-FreshServiceAsset` | Exact display ID plus the updatable properties in §6.2 | `FreshservicePSU.Asset` | Sends changed fields only; `ShouldProcess`; no type change |
| `Remove-FreshServiceAsset` | Exact asset display ID | none | Soft delete only; `ShouldProcess`; ConfirmImpact High; no restore or delete-forever |
| `Get-FreshServiceRequestedItem` | `-TicketId` plus `-PerPage`/`-MaxRecords` | `FreshservicePSU.RequestedItem` | Parent-scoped bounded read; output contract in §6.15 |
| `Get-FreshServiceTask` | `-TicketId` and optional `-Id` plus `-PerPage`/`-MaxRecords` | `FreshservicePSU.Task` | Ticket tasks only; parent-scoped bounded read; output contract in §6.16 |
| `Get-FreshServiceRequestApproval` | `-TicketId` and optional `-Id` plus `-PerPage`/`-MaxRecords` | `FreshservicePSU.Approval` | Parent-scoped bounded read; no approval actions; output contract in §6.17 |
| `Search-FreshServiceApproval` | At least one of `-ApproverId`/`-Status`/`-ParentId`/`-DelegateeId`; `parent=ticket` | `FreshservicePSU.Approval` | Q8 feature gate; numbered paging; `FreshservicePSU.Approval.SearchUnavailable` on require_feature/405; output contract in §6.17 |
| `Get-FreshServiceTicketActivity` | `-TicketId` plus `-MaxRecords` | `FreshservicePSU.TicketActivity` | Continuation-token pagination; output contract in §6.18 |
| `Get-FreshServiceSLAPolicy` | `-PerPage`/`-MaxRecords` | `FreshservicePSU.SLAPolicy` | Configuration read; `FreshservicePSU.SLAPolicy.Unavailable` on require_feature/405; output contract in §6.19 |
| `Get-FreshServiceBusinessHour` | `-Id`, or `-PerPage`/`-MaxRecords` | `FreshservicePSU.BusinessHour` | Configuration read; `FreshservicePSU.BusinessHour.Unavailable` on require_feature/405; output contract in §6.20 |

Every stable output type guarantees its resource identifier, display label when
the resource has one, relevant relationship identifiers, state or status, and
relevant timestamps. Exact property names and .NET types are recorded beside
each command's implementation. Additional vendor attributes may pass
through without becoming compatibility guarantees.

Every generated help topic includes at least one PSU-focused example, paging or
record-limit behavior, cache behavior, conditional properties and API-credit
costs, normalized errors, required Freshservice endpoint permission or feature
gate, and mutation safety where applicable.

## 6. Accepted field, lookup, and embed contracts

These lists are closed decisions. A parameter outside them is not added to a
public command without a new accepted scope decision. Every field below is
mapped to its exact Freshservice v2 request field during implementation, and
request-body contract tests prove that a field the caller did not supply is
never sent.

### 6.1 Ticket create and update fields

`New-FreshServiceTicket` requires a requester identity (requester ID or email),
`Subject`, and `Description`. Both `New-FreshServiceTicket` and
`Set-FreshServiceTicket` additionally accept:

| Group | Fields |
| --- | --- |
| Classification | `Status`, `Priority`, `Type`, `Source`, `Urgency`, `Impact` |
| Assignment | `GroupId`, `AgentId` (the `responder_id` field) |
| Categorization | `Category`, `SubCategory`, `ItemCategory`, `Tags` |
| Relationships | `DepartmentId`, `AssetDisplayId` |
| Scheduling | `DueBy`, `FirstResponseDueBy` |
| Extension | `CustomFields`, validated against `Get-FreshServiceTicketField` |

`Set-FreshServiceTicket` also accepts `Subject`, `Description`, and
`RequesterId`, and closing a ticket is an ordinary `Status` update rather than a
separate parameter or command.

Deliberately excluded: `workspace_id` (single-workspace tenant), attachments and
`email_config_id` (out of scope), `cc_emails`/`reply_cc_emails` (reply
behavior, not ticket state), and every read-only or system-computed field such
as SLA timestamps, `spam`, and `deleted`.

### 6.2 Updatable asset properties

`Set-FreshServiceAsset` accepts `AssetTag`, `Name`, `Description`,
`UsageType`, `Impact`, `LocationId`, `DepartmentId`, `AgentId` (assigned
agent), `UserId` (used-by requester), `GroupId`, and `AssignedOn`.
Allowlisted type-specific fields are added when
`Get-FreshServiceAssetType` can resolve them.

Deliberately excluded from this command: changing an asset's type,
creating, deleting, restoring, permanently deleting, or moving an
asset, and writing arbitrary unvalidated properties. Soft delete is
`Remove-FreshServiceAsset`. There is no external-synchronization mode.

### 6.3 Ticket embeds

`Get-FreshServiceTicket` exposes three opt-in embeds: `Requester`, `Stats`, and
`Conversations`. They are validated as a set, may be combined, and any other
value is rejected. Each embed costs additional API credits (§11 of
`ARCHITECTURE.md`): +1 on a single-ticket read, +2 on a list read. Requested
items, tasks, approvals, and activity have dedicated commands and are never
exposed as embeds.

### 6.4 Asset lookup parameter sets

`Get-FreshServiceAsset` has four mutually exclusive parameter sets:
`DisplayId`, `AssetTag`, `SerialNumber`, and a bounded validated `Filter` for
list retrieval. The first three are exact lookups. There is no mode parameter
that selects a different endpoint, and no parameter set reaches components,
requests, contracts, or relationships.

### 6.5 Location output

`Get-FreshServiceLocation` guarantees these properties on
`FreshservicePSU.Location`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number (`Int64` when present) | `id` |
| `Name` | string | `name` |
| `ParentLocationId` | number or `$null` | `parent_location_id` |
| `PrimaryContactId` | number or `$null` | `primary_contact_id` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |
| `UpdatedAt` | `DateTime` UTC or `$null` | `updated_at` |

`Address`, `ContactName`, `Email`, `Phone`, and `Primary` may appear when
the vendor sends them and are not compatibility guarantees.
`workspace_id` is not part of the public contract.

### 6.6 Ticket output

`Get-FreshServiceTicket` guarantees these properties on
`FreshservicePSU.Ticket`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number (`Int64` when present) | `id` |
| `Subject` | string | `subject` |
| `Status` | number or `$null` | `status` |
| `Priority` | number or `$null` | `priority` |
| `Type` | string or `$null` | `type` |
| `RequesterId` | number or `$null` | `requester_id` |
| `ResponderId` | number or `$null` | `responder_id` |
| `GroupId` | number or `$null` | `group_id` |
| `DepartmentId` | number or `$null` | `department_id` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |
| `UpdatedAt` | `DateTime` UTC or `$null` | `updated_at` |
| `DueBy` | `DateTime` UTC or `$null` | `due_by` |
| `FirstResponseDueBy` | `DateTime` UTC or `$null` | `fr_due_by` |

`Requester`, `Stats`, and `Conversations` appear only when `-Include`
requests them and are not compatibility guarantees. `Description` and
`CustomFields` may pass through and are not contractual.
`workspace_id` is not part of the public contract.

### 6.7 Ticket field output

`Get-FreshServiceTicketField` guarantees these properties on
`FreshservicePSU.TicketField`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number (`Int64` when present) | `id` |
| `Name` | string | `name` |
| `Label` | string | `label` |
| `FieldType` | string | `field_type` |
| `Required` | boolean or `$null` | `required`, else `required_for_agents` |
| `DefaultField` | boolean or `$null` | `default_field` |
| `Choices` | array (possibly empty) | `choices` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |
| `UpdatedAt` | `DateTime` UTC or `$null` | `updated_at` |

`Description` and `NestedFields` may pass through and are not contractual.
`workspace_id` is not part of the public contract.

### 6.8 Agent group output

`Get-FreshServiceAgentGroup` guarantees these properties on
`FreshservicePSU.AgentGroup`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number | `id` |
| `Name` | string | `name` |
| `Description` | string or `$null` | `description` |
| `Restricted` | boolean or `$null` | `restricted` |
| `EscalateTo` | number or `$null` | `escalate_to` |
| `BusinessHoursId` | number or `$null` | `business_hours_id` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |
| `UpdatedAt` | `DateTime` UTC or `$null` | `updated_at` |

`Members` and `Leaders` may pass through and are not contractual.

### 6.9 Department output

`Get-FreshServiceDepartment` guarantees these properties on
`FreshservicePSU.Department`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number | `id` |
| `Name` | string | `name` |
| `Description` | string or `$null` | `description` |
| `HeadUserId` | number or `$null` | `head_user_id` |
| `PrimeUserId` | number or `$null` | `prime_user_id` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |
| `UpdatedAt` | `DateTime` UTC or `$null` | `updated_at` |

`Domains` and `CustomFields` may pass through and are not contractual.

### 6.10 Agent output

`Get-FreshServiceAgent` guarantees these properties on
`FreshservicePSU.Agent`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number | `id` |
| `FirstName` | string or `$null` | `first_name` |
| `LastName` | string or `$null` | `last_name` |
| `Email` | string or `$null` | `email` |
| `Active` | boolean or `$null` | `active` |
| `JobTitle` | string or `$null` | `job_title` |
| `DepartmentIds` | array or `$null` | `department_ids` |
| `LocationId` | number or `$null` | `location_id` |
| `ReportingManagerId` | number or `$null` | `reporting_manager_id` |

`Occasional`, `LastLoginAt`, and `MemberOf` may pass through and are not
contractual. Lifecycle actions are out of scope.

### 6.11 Requester output

`Get-FreshServiceRequester` guarantees these properties on
`FreshservicePSU.Requester`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number | `id` |
| `FirstName` | string or `$null` | `first_name` |
| `LastName` | string or `$null` | `last_name` |
| `Email` | string or `$null` | `primary_email` |
| `Active` | boolean or `$null` | `active` |
| `JobTitle` | string or `$null` | `job_title` |
| `DepartmentIds` | array or `$null` | `department_ids` |
| `LocationId` | number or `$null` | `location_id` |
| `ReportingManagerId` | number or `$null` | `reporting_manager_id` |

`IsAgent` may pass through and is not contractual. Requester fields and
lifecycle actions are out of scope. `workspace_id` is not part of the
public contract.

### 6.12 Asset output

`Get-FreshServiceAsset` guarantees these properties on
`FreshservicePSU.Asset`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number | `id` |
| `DisplayId` | number | `display_id` |
| `Name` | string or `$null` | `name` |
| `AssetTag` | string or `$null` | `asset_tag` |
| `AssetTypeId` | number or `$null` | `asset_type_id` |
| `UsageType` | string or `$null` | `usage_type` |
| `Impact` | string or `$null` | `impact` |
| `LocationId` | number or `$null` | `location_id` |
| `DepartmentId` | number or `$null` | `department_id` |
| `AgentId` | number or `$null` | `agent_id` |
| `UserId` | number or `$null` | `user_id` |
| `GroupId` | number or `$null` | `group_id` |
| `AssignedOn` | `DateTime` UTC or `$null` | `assigned_on` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |
| `UpdatedAt` | `DateTime` UTC or `$null` | `updated_at` |

`Description` and `TypeFields` may pass through and are not contractual.
`workspace_id` is not part of the public contract. Components, requests,
contracts, and relationships are outside this command.

### 6.13 Asset type output

`Get-FreshServiceAssetType` guarantees these properties on
`FreshservicePSU.AssetType`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number | `id` |
| `Name` | string | `name` |
| `ParentAssetTypeId` | number or `$null` | `parent_asset_type_id` |
| `Description` | string or `$null` | `description` |
| `Visible` | boolean or `$null` | `visible` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |
| `UpdatedAt` | `DateTime` UTC or `$null` | `updated_at` |

Asset-type fields are a different resource and are not part of this
command. `workspace_id` is not part of the public contract.

### 6.14 Asset assignment history output

`Get-FreshServiceAssetAssignmentHistory` guarantees these properties on
`FreshservicePSU.AssetAssignmentHistory`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number | `id` |
| `DisplayId` | number | caller `-DisplayId`, or `display_id` when the vendor sends it |
| `UserId` | number or `$null` | `user_id` |
| `UserName` | string or `$null` | `user_name` |
| `AssignedOn` | `DateTime` UTC or `$null` | `assigned_on` |
| `AssignedBy` | number or `$null` | `assigned_by` |
| `AssignedByName` | string or `$null` | `assigned_by_name` |
| `UnassignedBy` | number or `$null` | `unassigned_by` |
| `UnassignedByName` | string or `$null` | `unassigned_by_name` |
| `UnassignedOn` | `DateTime` UTC or `$null` | `unassigned_on` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |
| `UpdatedAt` | `DateTime` UTC or `$null` | `updated_at` |

`workspace_id` is not part of the public contract.

### 6.15 Requested item output

`Get-FreshServiceRequestedItem` guarantees these properties on
`FreshservicePSU.RequestedItem`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number | `id` |
| `TicketId` | number | caller `-TicketId`, or `ticket_id` when the vendor sends it |
| `ServiceItemId` | number or `$null` | `service_item_id` |
| `Quantity` | number or `$null` | `quantity` |
| `Stage` | number or `$null` | `stage` |
| `Loaned` | boolean or `$null` | `loaned` |
| `CostPerRequest` | number or `$null` | `cost_per_request` |
| `IsParent` | boolean or `$null` | `is_parent` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |
| `UpdatedAt` | `DateTime` UTC or `$null` | `updated_at` |

`Remarks` and `CustomFields` may pass through and are not contractual.

### 6.16 Ticket task output

`Get-FreshServiceTask` guarantees these properties on
`FreshservicePSU.Task`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number | `id` |
| `TicketId` | number | caller `-TicketId`, or `ticket_id` when the vendor sends it |
| `Title` | string or `$null` | `title` |
| `Status` | number or `$null` | `status` |
| `AgentId` | number or `$null` | `agent_id` |
| `GroupId` | number or `$null` | `group_id` |
| `DueDate` | `DateTime` UTC or `$null` | `due_date` |
| `ClosedAt` | `DateTime` UTC or `$null` | `closed_at` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |
| `UpdatedAt` | `DateTime` UTC or `$null` | `updated_at` |

`Description` may pass through and is not contractual.

### 6.17 Approval output

`Get-FreshServiceRequestApproval` and `Search-FreshServiceApproval`
guarantee these properties on `FreshservicePSU.Approval`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number | `id` |
| `TicketId` | number or `$null` | `parent_id`, else caller `-TicketId` |
| `ApproverId` | number or `$null` | `approver_id` |
| `ApproverName` | string or `$null` | `approver_name` |
| `UserId` | number or `$null` | `user_id` |
| `UserName` | string or `$null` | `user_name` |
| `ApprovalStatusId` | number or `$null` | `approval_status.id` |
| `ApprovalStatusName` | string or `$null` | `approval_status.name` |
| `Level` | number or `$null` | `level` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |
| `UpdatedAt` | `DateTime` UTC or `$null` | `updated_at` |

`Delegatee`, `ApprovalGroup`, and `LatestRemark` may pass through and
are not contractual.

### 6.18 Ticket activity output

`Get-FreshServiceTicketActivity` guarantees these properties on
`FreshservicePSU.TicketActivity`:

| Property | Type | Source |
| --- | --- | --- |
| `TicketId` | number | caller `-TicketId` |
| `ActorId` | number or `$null` | `actor.id` |
| `ActorName` | string or `$null` | `actor.name` |
| `Content` | string or `$null` | `content` |
| `SubContents` | array or `$null` | `sub_contents` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |

Continuation tokens are never part of the public contract.

### 6.19 SLA policy output

`Get-FreshServiceSLAPolicy` guarantees these properties on
`FreshservicePSU.SLAPolicy`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number | `id` |
| `Name` | string | `name` |
| `Position` | number or `$null` | `position` |
| `IsDefault` | boolean or `$null` | `is_default` |
| `Active` | boolean or `$null` | `active` |
| `Deleted` | boolean or `$null` | `deleted` |
| `Description` | string or `$null` | `description` |

`SlaTargets` and `ApplicableTo` may pass through and are not
contractual. `workspace_id` is not part of the public contract.

### 6.20 Business hours output

`Get-FreshServiceBusinessHour` guarantees these properties on
`FreshservicePSU.BusinessHour`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number | `id` |
| `Name` | string | `name` |
| `Description` | string or `$null` | `description` |
| `IsDefault` | boolean or `$null` | `is_default` |
| `TimeZone` | string or `$null` | `time_zone` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |
| `UpdatedAt` | `DateTime` UTC or `$null` | `updated_at` |

`ServiceDeskHours` and `ListOfHolidays` may pass through and are not
contractual. `workspace_id` is not part of the public contract.

### 6.21 Ticket note output

`Add-FreshServiceTicketNote` guarantees these properties on
`FreshservicePSU.TicketNote`:

| Property | Type | Source |
| --- | --- | --- |
| `Id` | number | `id` |
| `TicketId` | number | `ticket_id`, else caller `-TicketId` |
| `Body` | string or `$null` | `body_text`, else `body` |
| `Private` | boolean or `$null` | `private` |
| `UserId` | number or `$null` | `user_id` |
| `Incoming` | boolean or `$null` | `incoming` |
| `CreatedAt` | `DateTime` UTC or `$null` | `created_at` |
| `UpdatedAt` | `DateTime` UTC or `$null` | `updated_at` |

Attachments and reply fields are outside this command.

## 7. Contract shared by every command

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

## 8. Export rule

The module exports exactly the 23 commands in this reference and no generated aliases. Two of them are provisional until Phase 1 sandbox evidence lands: `Search-FreshServiceApproval` (`OPEN_QUESTIONS.md` Q8) and `Get-FreshServiceAssetAssignmentHistory` (Q9) are removed, reducing the count, if the tenant cannot support their endpoints. CSAT remains conditional rather than committed, and time entries remain out of scope. Other Freshservice API operations are outside the app's supported public surface.

# FreshservicePSU command prune list

- **Status:** Accepted command-surface decision
- **Date:** 2026-08-12
- **Architecture:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Target command catalog:** [SUPPORTED_COMMANDS.md](SUPPORTED_COMMANDS.md)

This document records which commands the new major keeps and which it removes, and why. It is the source for the release migration notes and for the `NoLegacyReferences` regression guard (`tests/Architecture/NoLegacyReferences.Tests.ps1`), which derives its removed-name list from §4 below.

## 1. Decision rule

The module has 165 legacy public commands. The new major is a PSU integration for the named workloads in `CLAUDE.md`: create a ticket, add a ticket note, close or otherwise update a ticket, read tickets and their approvals, fulfillment, policies, and people for reporting, and read and update ordinary asset properties from authorized PSU apps and automations. A command is supported only when one of those workloads, its form, or a required report dimension uses it. Speculation about a future report does not establish scope; add a command with the shared authoring pattern when a concrete workload needs it, and update this record.

Result: **23 final exports** — 17 legacy names carried forward (rewritten against the new pipeline), 4 replace modes embedded in legacy commands, 2 cover newly selected endpoints with no legacy command. **148 legacy command names are removed or replaced** (147 with no final export under the same responsibility; `New-FreshServiceConversation` is replaced by `Add-FreshServiceTicketNote`).

## 2. Final supported commands

This table, not the legacy inventory, is the authoritative `FunctionsToExport` target.

| Final command | Method and endpoint | Workload |
| --- | --- | --- |
| `New-FreshServiceTicket` | `POST /tickets` | Create a ticket. |
| `Set-FreshServiceTicket` | `PUT /tickets/{id}` | Update or close a ticket. |
| `Get-FreshServiceTicket` | `GET /tickets/{id}` and bounded `GET /tickets` | Read one ticket or stream a bounded list. |
| `Search-FreshServiceTicket` | `GET /tickets/filter` | Filtered ticket retrieval for reports. |
| `Add-FreshServiceTicketNote` | `POST /tickets/{id}/notes` | Add a private or public note. The legacy reply mode is not retained. |
| `Get-FreshServiceTicketField` | `GET /ticket_form_fields` | Dynamic ticket forms and field-value resolution. |
| `Get-FreshServiceAgentGroup` | `GET /groups[/{id}]` | Assignment form values and report dimension. |
| `Get-FreshServiceDepartment` | `GET /departments[/{id}]` | Form values and report dimension. |
| `Get-FreshServiceLocation` | `GET /locations[/{id}]` | Form values and report dimension. |
| `Get-FreshServiceAgent` | `GET /agents[/{id}]` | Assignee labels, filters, workload, and performance reports. |
| `Get-FreshServiceRequester` | `GET /requesters[/{id}]` | Requester-level reporting and report enrichment. |
| `Get-FreshServiceAsset` | `GET /assets[/{display_id}]` | Incident reporting by asset, model, and location. |
| `Get-FreshServiceRequestedItem` | `GET /tickets/{ticket_id}/requested_items` | Catalog demand and fulfillment reports. |
| `Get-FreshServiceTask` | `GET /tickets/{ticket_id}/tasks[/{id}]` | Ticket-task backlog and fulfillment-duration reports. |
| `Get-FreshServiceRequestApproval` | `GET /tickets/{ticket_id}/approvals[/{id}]` | Approval aging and bottleneck reports. |
| `Get-FreshServiceSLAPolicy` | `GET /sla_policies` | SLA configuration and policy reports. |
| `Get-FreshServiceBusinessHour` | `GET /business_hours[/{id}]` | Business-hours configuration and policy reports. |
| `Get-FreshServiceTicketActivity` | `GET /tickets/{id}/activities` | Ticket history views and scheduled reporting. |
| `Set-FreshServiceAsset` | `PUT /assets/{display_id}` | Controlled asset updates from authorized PSU apps and automations. |
| `Remove-FreshServiceAsset` | `DELETE /assets/{display_id}` | Soft-delete an asset from authorized PSU apps and automations. |
| `Get-FreshServiceAssetType` | `GET /asset_types[/{id}]` | Asset forms, filters, and validation. |
| `Get-FreshServiceAssetAssignmentHistory` | `GET /assets/{display_id}/assignment-history` | Asset assignment audit and reporting. |
| `Search-FreshServiceApproval` | `GET /approvals` | Filtered cross-ticket approval queues and aging reports. |

Ticket deletion and restore are not supported. Closing a ticket is a status update, and no intended workload deletes tickets.

## 3. Legacy-to-final mapping (renamed or reshaped, not dropped)

| Legacy surface | Decision |
| --- | --- |
| `Get-FreshServiceTicket -Filter` | Replaced by `Search-FreshServiceTicket`. |
| `Get-FreshServiceTicket -Fields` | Replaced by `Get-FreshServiceTicketField`. |
| `Get-FreshServiceTicket -Activities` | Replaced by `Get-FreshServiceTicketActivity`. |
| `New-FreshServiceConversation -As Note` | Replaced by `Add-FreshServiceTicketNote`; reply mode removed. |
| Asset assignment history endpoint | No legacy command existed; added as `Get-FreshServiceAssetAssignmentHistory`. |
| Global approval endpoint | No legacy command existed; added as `Search-FreshServiceApproval`. |
| Connection/profile commands | Removed. The PSU host adapter supplies an ephemeral execution context. |
| Automatically generated aliases | Removed. The manifest explicitly exports no aliases. |

Every other final command (`New-FreshServiceTicket`, `Set-FreshServiceTicket`, `Get-FreshServiceTicket`, the reference-data reads, and the asset/fulfillment/approval/policy reads) keeps its legacy name and is rewritten as a single-purpose command against the new pipeline, with mode switches for unrelated endpoints (components, requests, contracts, relationships, agent/requester field variants, etc.) removed.

## 4. Removed legacy commands, by reason

### No intended workload (reads with no PSU consumer; addable later if a workload needs them)

`Get-FreshServiceAgentGroupMember`, `Get-FreshServiceAgentRole`, `Get-FreshServiceAnnouncement`, `Get-FreshServiceCannedResponse`, `Get-FreshServiceCannedResponseFolder`, `Get-FreshServiceChange`, `Get-FreshServiceContract`, `Get-FreshServiceContractType`, `Get-FreshServiceConversation`, `Get-FreshServiceCustomObject`, `Get-FreshServiceCustomObjectRecord`, `Get-FreshServiceProblem`, `Get-FreshServiceProduct`, `Get-FreshServiceProject`, `Get-FreshServiceProjectTask`, `Get-FreshServicePurchaseOrder`, `Get-FreshServiceRelationship`, `Get-FreshServiceRelationshipType`, `Get-FreshServiceRequesterGroup`, `Get-FreshServiceRequesterGroupMember`, `Get-FreshServiceCatalogCategory`, `Get-FreshServiceCatalogItem`, `Get-FreshServiceSoftware`, `Get-FreshServiceSoftwareInstallation`, `Get-FreshServiceSoftwareUser`, `Get-FreshServiceSolutionArticle`, `Get-FreshServiceSolutionCategory`, `Get-FreshServiceSolutionFolder`, `Get-FreshServiceNote`, `Get-FreshServiceVendor`.

### Write or action outside the ticket and note workloads

Grouped by resource family:

- **Agent Groups** (`/groups`): `Add-FreshServiceAgentGroupMember`, `New-FreshServiceAgentGroup`, `Remove-FreshServiceAgentGroup`, `Remove-FreshServiceAgentGroupMember`, `Set-FreshServiceAgentGroup`
- **Agents** (`/agents`): `New-FreshServiceAgent`, `Remove-FreshServiceAgent`, `Set-FreshServiceAgent`
- **Announcements** (`/announcements`): `New-FreshServiceAnnouncement`, `Remove-FreshServiceAnnouncement`, `Set-FreshServiceAnnouncement`
- **AssetTypes** (`/asset_types`): `New-FreshServiceAssetType`, `Remove-FreshServiceAssetType`, `Set-FreshServiceAssetType`
- **Assets** (`/assets`): `New-FreshServiceAsset`; `Restore-FreshServiceAsset` (restore stays out of scope — delete is one-way soft delete)
- **Audit Logs** (`/audit_log/export`): `Invoke-FreshServiceAuditLogExport`
- **Changes** (`/changes`): `New-FreshServiceChange`, `Remove-FreshServiceChange`, `Restore-FreshServiceChange`, `Set-FreshServiceChange`
- **Contract** (`/contracts`): `New-FreshServiceContract`, `Set-FreshServiceContract`
- **Conversations** (`/conversations`): `Remove-FreshServiceConversation`, `Set-FreshServiceConversation`
- **Custom Objects** (`/objects`): `New-FreshServiceCustomObjectRecord`, `Remove-FreshServiceCustomObjectRecord`, `Set-FreshServiceCustomObjectRecord`
- **Departments** (`/departments`): `New-FreshServiceDepartment`, `Remove-FreshServiceDepartment`, `Set-FreshServiceDepartment`
- **Locations** (`/locations`): `New-FreshServiceLocation`, `Remove-FreshServiceLocation`, `Set-FreshServiceLocation`
- **Problems** (`/problems`): `New-FreshServiceProblem`, `Remove-FreshServiceProblem`, `Restore-FreshServiceProblem`, `Set-FreshServiceProblem`
- **Products** (`/products`): `New-FreshServiceProduct`, `Remove-FreshServiceProduct`, `Set-FreshServiceProduct`
- **Projects** (`/pm/projects`): `New-FreshServiceProject`, `New-FreshServiceProjectTask`, `Remove-FreshServiceProject`, `Remove-FreshServiceProjectTask`, `Restore-FreshServiceProject`, `Set-FreshServiceProject`, `Set-FreshServiceProjectTask`
- **PurchaseOrders** (`/purchase_orders`): `New-FreshServicePurchaseOrder`, `Remove-FreshServicePurchaseOrder`, `Set-FreshServicePurchaseOrder`
- **Relationships** (`/relationships`): `New-FreshServiceRelationship`, `Remove-FreshServiceRelationship`
- **Requester Groups** (`/requester_groups`): `Add-FreshServiceRequesterGroupMember`, `New-FreshServiceRequesterGroup`, `Remove-FreshServiceRequesterGroup`, `Remove-FreshServiceRequesterGroupMember`
- **Requesters** (`/requesters`, `/requester_groups`): `New-FreshServiceRequester`, `Remove-FreshServiceRequester`, `Set-FreshServiceRequester`, `Set-FreshServiceRequesterGroup`
- **Software** (`/applications`): `New-FreshServiceSoftware`, `New-FreshServiceSoftwareInstallation`, `New-FreshServiceSoftwareUser`, `Remove-FreshServiceSoftware`, `Remove-FreshServiceSoftwareInstallation`, `Remove-FreshServiceSoftwareUser`, `Set-FreshServiceSoftware`, `Set-FreshServiceSoftwareUser`
- **Solution Article** (`/solutions/articles`): `New-FreshServiceSolutionArticle`, `Remove-FreshServiceSolutionArticle`, `Set-FreshServiceSolutionArticle`
- **Solution Category** (`/solutions/categories`): `New-FreshServiceSolutionCategory`, `Remove-FreshServiceSolutionCategory`, `Set-FreshServiceSolutionCategory`
- **Solution Folder** (`/solutions/folders`): `New-FreshServiceSolutionFolder`, `Remove-FreshServiceSolutionFolder`, `Set-FreshServiceSolutionFolder`
- **Tickets** (notes/tasks/requests/approvals, not time entries): `New-FreshServiceNote`, `Remove-FreshServiceNote`, `Set-FreshServiceNote`, `New-FreshServiceOnboardingRequest`, `New-FreshServiceRequest`, `New-FreshServiceRequestApproval`, `Set-FreshServiceRequestApproval`, `New-FreshServiceTask`, `Remove-FreshServiceTask`, `Set-FreshServiceTask`, `New-FreshServiceTicketSource`, `Remove-FreshServiceTicket`, `Restore-FreshServiceTicket`, `Set-FreshServiceRequestedItem`
- **Vendors** (`/vendors`): `New-FreshServiceVendor`, `Remove-FreshServiceVendor`, `Set-FreshServiceVendor`

### Out-of-scope family (removed in full, including reads)

- **Releases**: `Get-FreshServiceRelease`, `New-FreshServiceRelease`, `Remove-FreshServiceRelease`, `Restore-FreshServiceRelease`, `Set-FreshServiceRelease`
- **Time entries**: `Get-FreshServiceTimeEntry`, `New-FreshServiceTimeEntry`, `Remove-FreshServiceTimeEntry`, `Set-FreshServiceTimeEntry`
- **Employee onboarding**: `Get-FreshServiceOnboardingRequest` (not implemented in the tenant)
- **Single workspace**: `Get-FreshServiceWorkspace`

### Legacy connection architecture (replaced by the PSU host adapter)

`Connect-FreshService`, `Get-FreshServiceConnection`, `Get-FreshServiceInfo`, `New-FreshServiceConnection`, `Remove-FreshServiceConnection`, `Set-FreshServiceConnection`. `Get-FreshServiceInfo`'s rate-limit probe becomes response-header telemetry in the request pipeline (`ARCHITECTURE.md` §11).

### Local helper, no API call (folded into parent-command parameter validation)

`New-FreshServiceAgentRoleConfig`, `New-FreshServiceContractItem`, `New-FreshServicePurchaseItem`, `New-FreshServiceRelationshipItem`

### Polls bulk relationship writes (nothing left to poll once those writes are removed)

`Get-FreshServiceBackgroundJob`

## 5. If a removed command is needed later

Add it with the shared command-authoring pattern rather than restoring the deleted file — the old implementation carries the legacy transport, connection guard, hand-rolled pagination, and untyped output the new architecture prohibits. Update `SUPPORTED_COMMANDS.md`, `FunctionsToExport`, this prune list, and the endpoint decision CSV in the same change.

The removed implementation remains visible in Git history. The upstream `FreshservicePS` Gallery package is a separate project identity and is not a previous published major of `FreshservicePSU`.

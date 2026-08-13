# FreshservicePSU command prune list

- **Status:** Accepted command-surface decision
- **Date:** 2026-08-12
- **Architecture:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Target command catalog:** [SUPPORTED_COMMANDS.md](SUPPORTED_COMMANDS.md)
- **Sequencing:** [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) Phase 2 removes legacy code; Phases 5 and 6 build the supported reads and mutations

This document records which commands the new major keeps and which it removes, and why. It is the source for the release migration notes.

## 1. Decision rule

The module has 165 legacy public commands. The new major is a PSU integration for the named workloads in `CLAUDE.md`: create a ticket, add a ticket note, close or otherwise update a ticket, read tickets and their approvals, fulfillment, policies, and people for reporting, and read and update ordinary asset properties from authorized PSU apps and automations. A command is supported only when one of those workloads, its form, or a required report dimension uses it.

Reads do not change Freshservice authorship, but they are not risk-free or free to maintain. They expose tenant data, consume endpoint rate limits, and still require PSU authentication, operation-specific authorization, credential selection, tenant isolation, audit records, typed outputs, pagination limits, error normalization, tests, and help. Only non-secret, non-permission-filtered reference data may use the bounded cache defined in ARCHITECTURE §11.

Speculation about a future report does not establish scope. When a concrete PSU workload needs another command, add it with the shared command-authoring pattern and update this decision record.

Result:

- **22 final exports.**
- **16 legacy command names carry forward**, rewritten against the new pipeline.
- **4 final commands replace modes embedded in legacy commands.**
- **2 final commands cover newly selected endpoints with no legacy command.**
- **149 legacy command names are removed or replaced.** Of these, 148 have no final export under the same responsibility, and `New-FreshServiceConversation` is replaced by `Add-FreshServiceTicketNote`.

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
| `Get-FreshServiceAssetType` | `GET /asset_types[/{id}]` | Asset forms, filters, and validation. |
| `Get-FreshServiceAssetAssignmentHistory` | `GET /assets/{display_id}/assignment-history` | Asset assignment audit and reporting. |
| `Search-FreshServiceApproval` | `GET /approvals` | Filtered cross-ticket approval queues and aging reports. |

Ticket deletion and restore are not supported. Closing a ticket is a status update, and no intended workload deletes tickets.

## 3. Legacy-to-final mapping

| Legacy surface | Decision |
| --- | --- |
| `New-FreshServiceTicket` | Keep the name; rewrite against the shared request pipeline. |
| `Set-FreshServiceTicket` | Keep the name; retain ordinary ticket updates, including close. Remove unrelated endpoint-selecting switches. |
| `Get-FreshServiceTicket` | Keep only single-ticket and bounded list behavior. |
| `Get-FreshServiceTicket -Filter` | Replace with `Search-FreshServiceTicket`. |
| `Get-FreshServiceTicket -Fields` | Replace with `Get-FreshServiceTicketField`. |
| `New-FreshServiceConversation -As Note` | Replace with `Add-FreshServiceTicketNote`; remove reply mode. |
| `Get-FreshServiceAgentGroup` | Keep the name; rewrite as a focused group read. |
| `Get-FreshServiceDepartment` | Keep the name; rewrite as a focused department read. |
| `Get-FreshServiceLocation` | Keep the name; rewrite as a focused location read. |
| `Get-FreshServiceAgent` | Keep the name; rewrite as a focused agent read for report dimensions. Remove legacy agent-field and unrelated mode behavior. |
| `Get-FreshServiceRequester` | Keep the name; rewrite as a focused requester read for reporting. Remove legacy requester-field and unrelated mode behavior. |
| `Get-FreshServiceAsset` | Keep the name; rewrite as a focused asset read. Remove switches that select component, request, contract, or relationship endpoints. |
| `Get-FreshServiceRequestedItem` | Keep the name; rewrite as a focused ticket requested-item read. |
| `Get-FreshServiceTask` | Keep the name; rewrite as a focused ticket-task read rather than multiplexing parent resource types. |
| `Get-FreshServiceRequestApproval` | Keep the name; rewrite as a focused ticket-approval read. |
| `Get-FreshServiceSLAPolicy` | Keep the name; rewrite as a focused SLA-policy read. |
| `Get-FreshServiceBusinessHour` | Keep the name; rewrite as a focused business-hours read. |
| `Get-FreshServiceTicket -Activities` | Replace with `Get-FreshServiceTicketActivity`. |
| `Set-FreshServiceAsset` | Keep the name; rewrite as a focused ordinary asset update with `ShouldProcess` and no delete, restore, move, or synchronization modes. |
| `Get-FreshServiceAssetType` | Keep the name; rewrite as a focused asset-type read without a fields mode. |
| Asset assignment history endpoint | Add `Get-FreshServiceAssetAssignmentHistory`; no legacy command exists. |
| Global approval endpoint | Add `Search-FreshServiceApproval`; no legacy command exists. |
| Connection/profile commands | Remove. The PSU host adapter supplies an ephemeral execution context. |
| Automatically generated aliases | Remove. The manifest explicitly exports no aliases. |

## 4. Removed legacy commands

### Unsupported reads

These reads have no current PSU consumer. They can be added later only when a named workload requires them.

| Command | Reason |
| --- | --- |
| `Get-FreshServiceAgentGroupMember` | No intended workload |
| `Get-FreshServiceAgentRole` | No intended workload |
| `Get-FreshServiceAnnouncement` | No intended workload |
| `Get-FreshServiceCannedResponse` | No intended workload |
| `Get-FreshServiceCannedResponseFolder` | No intended workload |
| `Get-FreshServiceChange` | No intended workload |
| `Get-FreshServiceContract` | No intended workload |
| `Get-FreshServiceContractType` | No intended workload |
| `Get-FreshServiceConversation` | Conversation history is not required by the intended workloads |
| `Get-FreshServiceCustomObject` | No intended workload |
| `Get-FreshServiceCustomObjectRecord` | No intended workload |
| `Get-FreshServiceProblem` | No intended workload |
| `Get-FreshServiceProduct` | No intended workload |
| `Get-FreshServiceProject` | No intended workload |
| `Get-FreshServiceProjectTask` | No intended workload |
| `Get-FreshServicePurchaseOrder` | No intended workload |
| `Get-FreshServiceRelationship` | No intended workload |
| `Get-FreshServiceRelationshipType` | No intended workload |
| `Get-FreshServiceRequesterGroup` | No intended workload |
| `Get-FreshServiceRequesterGroupMember` | No intended workload |
| `Get-FreshServiceCatalogCategory` | No intended workload |
| `Get-FreshServiceCatalogItem` | No intended workload |
| `Get-FreshServiceSoftware` | No intended workload |
| `Get-FreshServiceSoftwareInstallation` | No intended workload |
| `Get-FreshServiceSoftwareUser` | No intended workload |
| `Get-FreshServiceSolutionArticle` | No intended workload |
| `Get-FreshServiceSolutionCategory` | No intended workload |
| `Get-FreshServiceSolutionFolder` | No intended workload |
| `Get-FreshServiceNote` | Notes outside tickets are not required; ticket history is not an intended workload |
| `Get-FreshServiceVendor` | No intended workload |

### Agent Groups

| Command | Endpoint | Reason |
| --- | --- | --- |
| `Add-FreshServiceAgentGroupMember` | `/groups` | Write or action outside the ticket and note workloads |
| `New-FreshServiceAgentGroup` | `/groups` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceAgentGroup` | `/groups` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceAgentGroupMember` | `/groups` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceAgentGroup` | `/groups` | Write or action outside the ticket and note workloads |

### Agent Roles

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceAgentRoleConfig` | `— no API call —` | Local helper, no API call; folds into its parent parameter |

### Agents

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceAgent` | `/agents` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceAgent` | `/agents` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceAgent` | `/agents` | Write or action outside the ticket and note workloads |

### Announcements

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceAnnouncement` | `/announcements` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceAnnouncement` | `/announcements` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceAnnouncement` | `/announcements` | Write or action outside the ticket and note workloads |

### AssetTypes

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceAssetType` | `/asset_types` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceAssetType` | `/asset_types` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceAssetType` | `/asset_types` | Write or action outside the ticket and note workloads |

### Assets

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceAsset` | `/assets` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceAsset` | `/assets` | Write or action outside the ticket and note workloads |
| `Restore-FreshServiceAsset` | `/assets` | Write or action outside the ticket and note workloads |

### Audit Logs

| Command | Endpoint | Reason |
| --- | --- | --- |
| `Invoke-FreshServiceAuditLogExport` | `/audit_log/export` | Write or action outside the ticket and note workloads |

### Changes

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceChange` | `/changes` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceChange` | `/changes` | Write or action outside the ticket and note workloads |
| `Restore-FreshServiceChange` | `/changes` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceChange` | `/changes` | Write or action outside the ticket and note workloads |

### Connection

| Command | Endpoint | Reason |
| --- | --- | --- |
| `Connect-FreshService` | `— no API call —` | Legacy connection architecture; replaced by the PSU host adapter |
| `Get-FreshServiceConnection` | `— no API call —` | Legacy connection architecture; replaced by the PSU host adapter |
| `Get-FreshServiceInfo` | `/business_hours` | Legacy connection architecture; replaced by the PSU host adapter |
| `New-FreshServiceConnection` | `— no API call —` | Legacy connection architecture; replaced by the PSU host adapter |
| `Remove-FreshServiceConnection` | `— no API call —` | Legacy connection architecture; replaced by the PSU host adapter |
| `Set-FreshServiceConnection` | `— no API call —` | Legacy connection architecture; replaced by the PSU host adapter |

### Contract

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceContract` | `/contracts` | Write or action outside the ticket and note workloads |
| `New-FreshServiceContractItem` | `— no API call —` | Local helper, no API call; folds into its parent parameter |
| `Set-FreshServiceContract` | `/contracts` | Write or action outside the ticket and note workloads |

### Conversations

| Command | Endpoint | Reason |
| --- | --- | --- |
| `Remove-FreshServiceConversation` | `/conversations` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceConversation` | `/conversations` | Write or action outside the ticket and note workloads |

### Custom Objects

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceCustomObjectRecord` | `/objects` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceCustomObjectRecord` | `/objects` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceCustomObjectRecord` | `/objects` | Write or action outside the ticket and note workloads |

### Departments

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceDepartment` | `/departments` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceDepartment` | `/departments` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceDepartment` | `/departments` | Write or action outside the ticket and note workloads |

### Locations

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceLocation` | `/locations` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceLocation` | `/locations` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceLocation` | `/locations` | Write or action outside the ticket and note workloads |

### Onboarding Requests

| Command | Endpoint | Reason |
| --- | --- | --- |
| `Get-FreshServiceOnboardingRequest` | `/onboarding_requests` | Employee onboarding not implemented in the tenant |

### Problems

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceProblem` | `/problems` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceProblem` | `/problems` | Write or action outside the ticket and note workloads |
| `Restore-FreshServiceProblem` | `/problems` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceProblem` | `/problems` | Write or action outside the ticket and note workloads |

### Products

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceProduct` | `/products` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceProduct` | `/products` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceProduct` | `/products` | Write or action outside the ticket and note workloads |

### Projects

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceProject` | `/pm/projects` | Write or action outside the ticket and note workloads |
| `New-FreshServiceProjectTask` | `/pm/projects` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceProject` | `/pm/projects` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceProjectTask` | `/pm/projects` | Write or action outside the ticket and note workloads |
| `Restore-FreshServiceProject` | `/pm/projects` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceProject` | `/pm/projects` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceProjectTask` | `/pm/projects` | Write or action outside the ticket and note workloads |

### PurchaseOrders

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServicePurchaseItem` | `— no API call —` | Local helper, no API call; folds into its parent parameter |
| `New-FreshServicePurchaseOrder` | `/purchase_orders` | Write or action outside the ticket and note workloads |
| `Remove-FreshServicePurchaseOrder` | `/purchase_orders` | Write or action outside the ticket and note workloads |
| `Set-FreshServicePurchaseOrder` | `/purchase_orders` | Write or action outside the ticket and note workloads |

### Relationships

| Command | Endpoint | Reason |
| --- | --- | --- |
| `Get-FreshServiceBackgroundJob` | `/jobs` | Polls bulk relationship writes, which are removed |
| `New-FreshServiceRelationship` | `/relationships/bulk-create` | Write or action outside the ticket and note workloads |
| `New-FreshServiceRelationshipItem` | `— no API call —` | Local helper, no API call; folds into its parent parameter |
| `Remove-FreshServiceRelationship` | `/relationships` | Write or action outside the ticket and note workloads |

### Releases

| Command | Endpoint | Reason |
| --- | --- | --- |
| `Get-FreshServiceRelease` | `/release_form_fields / /releases` | Releases family is out of scope |
| `New-FreshServiceRelease` | `/releases` | Releases family is out of scope |
| `Remove-FreshServiceRelease` | `/releases` | Releases family is out of scope |
| `Restore-FreshServiceRelease` | `/releases` | Releases family is out of scope |
| `Set-FreshServiceRelease` | `/releases` | Releases family is out of scope |

### Requester Groups

| Command | Endpoint | Reason |
| --- | --- | --- |
| `Add-FreshServiceRequesterGroupMember` | `/requester_groups` | Write or action outside the ticket and note workloads |
| `New-FreshServiceRequesterGroup` | `/requester_groups` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceRequesterGroup` | `/requester_groups` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceRequesterGroupMember` | `/requester_groups` | Write or action outside the ticket and note workloads |

### Requesters

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceRequester` | `/requesters` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceRequester` | `/requesters` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceRequester` | `/requesters` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceRequesterGroup` | `/requester_groups` | Write or action outside the ticket and note workloads |

### Software

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceSoftware` | `/applications` | Write or action outside the ticket and note workloads |
| `New-FreshServiceSoftwareInstallation` | `/applications` | Write or action outside the ticket and note workloads |
| `New-FreshServiceSoftwareUser` | `/applications` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceSoftware` | `/applications` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceSoftwareInstallation` | `/applications` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceSoftwareUser` | `/applications` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceSoftware` | `/applications` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceSoftwareUser` | `/applications` | Write or action outside the ticket and note workloads |

### Solution Article

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceSolutionArticle` | `/solutions/articles` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceSolutionArticle` | `/solutions/articles` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceSolutionArticle` | `/solutions/articles` | Write or action outside the ticket and note workloads |

### Solution Category

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceSolutionCategory` | `/solutions/categories` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceSolutionCategory` | `/solutions/categories` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceSolutionCategory` | `/solutions/categories` | Write or action outside the ticket and note workloads |

### Solution Folder

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceSolutionFolder` | `/solutions/folders` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceSolutionFolder` | `/solutions/folders` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceSolutionFolder` | `/solutions/folders` | Write or action outside the ticket and note workloads |

### Tickets

| Command | Endpoint | Reason |
| --- | --- | --- |
| `Get-FreshServiceTimeEntry` | `/{1}s/{2}/time_entries` | Time entries out of scope |
| `New-FreshServiceNote` | `/{1}s/{2}\notes` | Write or action outside the ticket and note workloads |
| `New-FreshServiceOnboardingRequest` | `/onboarding_requests` | Write or action outside the ticket and note workloads |
| `New-FreshServiceRequest` | `/service_catalog/items/{1}/place_request` | Write or action outside the ticket and note workloads |
| `New-FreshServiceRequestApproval` | `/tickets/{1}/approvals` | Write or action outside the ticket and note workloads |
| `New-FreshServiceTask` | `/{1}s/{2}/tasks` | Write or action outside the ticket and note workloads |
| `New-FreshServiceTicketSource` | `/ticket_fields/sources` | Write or action outside the ticket and note workloads |
| `New-FreshServiceTimeEntry` | `/{1}s/{2}/time_entries` | Time entries out of scope |
| `Remove-FreshServiceNote` | `/{1}s/{2}/notes/{3}` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceTask` | `/{1}s/{2}/tasks/{3}` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceTicket` | `/tickets` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceTimeEntry` | `/{1}s/{2}/time_entries/{3}` | Time entries out of scope |
| `Restore-FreshServiceTicket` | `/tickets` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceNote` | `/{1}s/{2}\notes/{3}` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceRequestApproval` | `/tickets/{1}/approvals/{2}/remind / /tickets/{1}/approvals/{2}` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceRequestedItem` | `/tickets` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceTask` | `/{1}s/{2}/tasks/{3}` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceTimeEntry` | `/{1}s/{2}/time_entries/{3}` | Time entries out of scope |

### Vendors

| Command | Endpoint | Reason |
| --- | --- | --- |
| `New-FreshServiceVendor` | `/vendors` | Write or action outside the ticket and note workloads |
| `Remove-FreshServiceVendor` | `/vendors` | Write or action outside the ticket and note workloads |
| `Set-FreshServiceVendor` | `/vendors` | Write or action outside the ticket and note workloads |

### Workspaces

| Command | Endpoint | Reason |
| --- | --- | --- |
| `Get-FreshServiceWorkspace` | `/workspaces` | Single workspace |

## 5. Reason categories

| Reason | Meaning |
| --- | --- |
| No intended workload | The endpoint may be useful, but no current PSU page, report, form, or automation consumes it. Existing legacy coverage does not establish new-major scope. |
| Write or action outside the named PSU workloads | The operation has no named consumer. Reads in the same family are evaluated independently and are also removed unless a workload requires them. |
| Out-of-scope family | Releases, workspaces, employee onboarding, and time entries are removed in full, including reads. |
| Legacy connection architecture | `Connect-`, `New-`/`Get-`/`Set-`/`Remove-FreshServiceConnection` are replaced by the PSU host adapter and the ephemeral execution context. `Get-FreshServiceInfo` goes with them; its rate-limit probe becomes response-header telemetry in the request pipeline (ARCHITECTURE §11). |
| Local helper, no API call | `New-FreshServiceContractItem`, `…PurchaseItem`, `…RelationshipItem`, `…AgentRoleConfig` build hashtables and never call Freshservice. Their value moves into the parent command's parameter validation. |
| Polls bulk relationship writes | `Get-FreshServiceBackgroundJob` exists to poll async bulk relationship operations. With those writes removed it has nothing to poll. |

## 6. If a removed command is needed later

Add it with the shared command-authoring pattern rather than restoring the deleted file. The old implementation carries the legacy transport, connection guard, hand-rolled pagination, and untyped output the new architecture prohibits, so it requires a fresh implementation and proportionate unit, contract, PSU, and live-test coverage. Update `SUPPORTED_COMMANDS.md`, `FunctionsToExport`, this prune list, and the endpoint decision CSV in the same change.

The removed implementation remains visible in Git history. The upstream `FreshservicePS` Gallery package is a separate project identity and is not a previous published major of `FreshservicePSU`.

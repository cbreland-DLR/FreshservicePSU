# Freshservice API v2 endpoint coverage matrix

**Snapshot:** 2026-08-12  
**Official reference:** <https://api.freshservice.com/v2/>  
**How to use this file:** This is legacy endpoint evidence, not the target product backlog. `Implemented` means the inherited repository has a command that calls the documented endpoint family. `Partial` means at least one documented operation is absent, and `—` means no matching legacy command was found. Target-scope decisions are recorded in `FRESHSERVICE_API_V2_ENDPOINT_COMPARISON.csv`; `SUPPORTED_COMMANDS.md` remains authoritative for the completed public surface.

This comparison is scoped to **standard Freshservice**, not Freshservice for MSPs, to **API v2 only**, and to the **Enterprise plan**. Enterprise-gated endpoints are therefore in scope; MSP-only endpoints and earlier API versions are not. Some endpoint families still depend on tenant feature flags such as Workspaces; verify availability against the target tenant before implementation.

## Current module command inventory

The reviewed legacy module contains 165 public functions (and exports aliases for them). Its strongest coverage is core ITSM: tickets, conversations, problems, changes, releases, core assets, requesters, agents, and NewGen projects.

| API resource | Public commands currently present |
| --- | --- |
| Tickets | `Get/New/Set/Remove/Restore-FreshServiceTicket`, `New-FreshServiceRequest`, `Get/Set-FreshServiceRequestedItem`, `New-FreshServiceTicketSource`, `New-FreshServiceOnboardingRequest` |
| Ticket child resources | `Get/New/Set/Remove-FreshServiceNote`, `Get/New/Set/Remove-FreshServiceTask`, `Get/New/Set/Remove-FreshServiceTimeEntry`, `Get/New/Set-FreshServiceRequestApproval`, `Get-FreshServiceConversation`, `New/Set/Remove-FreshServiceConversation` |
| Problems, changes, releases | `Get/New/Set/Remove-FreshServiceProblem`, `Get/New/Set/Remove/Restore-FreshServiceChange`, `Get/New/Set/Remove/Restore-FreshServiceRelease` |
| People and groups | `Get/New/Set/Remove-FreshServiceRequester`, `Get/New/Set/Remove-FreshServiceAgent`, agent/requester group commands, `Get-FreshServiceAgentRole` |
| Assets and ITAM | `Get/New/Set/Remove/Restore-FreshServiceAsset`, `Get/New/Set/Remove-FreshServiceAssetType`, software, relationships, products, vendors, locations, departments, contracts, purchase orders |
| Projects | `Get/New/Set/Remove/Restore-FreshServiceProject`, `Get/New/Set/Remove-FreshServiceProjectTask` |
| Knowledge and catalog | Solution category/folder/article CRUD, `Get-FreshServiceCatalogItem`, `Get-FreshServiceCatalogCategory`, canned responses |
| Other | Workspaces (read), announcements CRUD, onboarding requests (read), custom-object records CRUD, business hours, SLA policies, audit-log export |

## Core service-desk endpoints

| Endpoint family / official operations | Project command(s) | Coverage | Missing operations or notes |
| --- | --- | --- | --- |
| `/tickets` — Create, view, filter, list, update, delete, restore | `Get/New/Set/Remove/Restore-FreshServiceTicket` | Implemented | `Get` also exposes ticket fields, activity, CSAT, and list/filter parameters. |
| `/tickets/{id}/move_workspace`, `/tickets/{id}/attachments/{id}` — move ticket; delete attachment | — | Missing | Add `Move-FreshServiceTicket`, `Remove-FreshServiceTicketAttachment`. |
| `/tickets/{parent_id}/create_child_ticket` — create child ticket | `New-FreshServiceTicket -parent_id` | Implemented | |
| `/ticket_form_fields`, `/tickets/{id}/activities`, `/tickets/{id}/csat_response` | `Get-FreshServiceTicket -fields/-Activities/-csat_response` | Implemented | |
| `/tickets/{id}/time_entries` and `/tickets/{id}/time_entries/{entry_id}` — CRUD time entries | `Get/New/Set/Remove-FreshServiceTimeEntry` | Implemented | The shared commands also cover the analogous problem/change/release operations. |
| `/tickets/{id}/tasks` and `/tickets/{id}/tasks/{task_id}` — CRUD tasks | `Get/New/Set/Remove-FreshServiceTask` | Implemented | The shared commands also cover the analogous problem/change/release operations. |
| `/tickets/{id}/requested_items` — view/update requested items | `Get/Set-FreshServiceRequestedItem` | Partial | Missing **add catalog item to existing service request**. |
| `/tickets/{id}/create_child_service_request` | — | Missing | Add `New-FreshServiceChildRequest`. |
| `/tickets/{id}/approvals` and `/tickets/{id}/approvals/{approval_id}` — create/list/view/remind/cancel | `Get/New/Set-FreshServiceRequestApproval` | Partial | Add single-approval retrieval, reminder, and cancellation commands; verify `Set` only updates an approval rather than covering all actions. |
| `/tickets/{id}/approval_groups` and approval-chain-rule actions | — | Missing | Create/update/list/cancel approval groups and update approval-chain rule. |
| Major-incident actions — promote/demote ticket | — | Missing | Add promote and demote commands. |
| `/ticket_sources` — create source | `New-FreshServiceTicketSource` | Implemented | |
| Conversations: `/tickets/{id}/conversations` and `/conversations/{id}` — reply, note, update, delete, list | `Get/New/Set/Remove-FreshServiceConversation` | Partial | Add delete-conversation-attachment endpoint. |
| Problem: `/problems`, `/problem_form_fields`, `/problems/{id}/move_workspace` — CRUD, fields, move, restore | `Get/New/Set/Remove/Restore-FreshServiceProblem` | Partial | `Get` declares `workspace_id` but does not use it; add move and verify workspace support. |
| Problem notes, time entries, and tasks | Shared `Get/New/Set/Remove-FreshServiceNote`, `...TimeEntry`, `...Task` | Implemented | |
| Change: `/changes`, `/change_form_fields`, `/changes/{id}/move_workspace` — CRUD, fields, move | `Get/New/Set/Remove/Restore-FreshServiceChange` | Partial | Add move; no documented restore operation is listed in the current v2 navigation. |
| Change approvals and approval groups | — | Missing | List/view/remind/cancel approvals; create/update/list/cancel approval groups; update chain rule. |
| Change notes, time entries, and tasks | Shared `Get/New/Set/Remove-FreshServiceNote`, `...TimeEntry`, `...Task` | Implemented | |
| Release: `/releases`, `/releases/filter`, `/release_form_fields`, `/releases/{id}/move_workspace` — CRUD, filter, fields, move, restore | `Get/New/Set/Remove/Restore-FreshServiceRelease` | Partial | Add move and explicit fields retrieval; confirm filter parameters against current documentation. |
| Release notes, time entries, and tasks | Shared `Get/New/Set/Remove-FreshServiceNote`, `...TimeEntry`, `...Task` | Implemented | |
| CABs — create, list, view, update, delete | — | Missing | Entire endpoint family. |
| Approvals — list all approvals | — | Missing | Global approval listing is not covered. |

## People, workspace, and administration endpoints

| Endpoint family / official operations | Project command(s) | Coverage | Missing operations or notes |
| --- | --- | --- | --- |
| Workspaces/clients: create, view, list, filter, update, delete, fields | `Get-FreshServiceWorkspace` | Partial | Read/list only. Add create/filter/update/delete/fields. |
| Requesters/contacts: create, view/list/filter/fields, update, deactivate, forget, convert to agent, merge, reactivate, assignment history | `Get/New/Set/Remove-FreshServiceRequester` | Partial | `Set` includes some lifecycle actions; add/verify forget, assignment history, and complete action coverage. |
| Agents: create, view/list/filter, update, deactivate, forget, reactivate, convert to requester, fields, assignment history | `Get/New/Set/Remove-FreshServiceAgent`, `Get-FreshServiceAgentRole` | Partial | Add/verify forget, conversion, fields, and assignment history. |
| Agent roles — view/list | `Get-FreshServiceAgentRole` | Partial | Module has a helper for role configuration, not an API role-management endpoint. |
| Agent groups — create, view/list, update, delete | `Get/New/Set/Remove-FreshServiceAgentGroup` plus membership commands | Implemented | Membership is managed through group-oriented helpers. |
| Requester/contact groups — create, view/list, update, delete, membership CRUD/list | `Get/New/Set/Remove-FreshServiceRequesterGroup`, member commands | Implemented | |
| Locations — CRUD plus filter | `Get/New/Set/Remove-FreshServiceLocation` | Partial | Add/verify documented filter semantics. |
| Departments/companies — CRUD, filter, fields | `Get/New/Set/Remove-FreshServiceDepartment` | Partial | Add/verify filter and fields endpoints. |
| Business hours — view one/list | `Get-FreshServiceBusinessHour` | Implemented | |
| SLA policies — list | `Get-FreshServiceSLAPolicy` | Implemented | |
| Announcements — CRUD | `Get/New/Set/Remove-FreshServiceAnnouncement` | Implemented | |
| Custom objects — list/view objects; create/list/update/delete records | `Get-FreshServiceCustomObject`, `Get/New/Set/Remove-FreshServiceCustomObjectRecord` | Implemented | |
| Audit logs — export | `Invoke-FreshServiceAuditLogExport` | Implemented | |

## Asset, inventory, and procurement endpoints

| Endpoint family / official operations | Project command(s) | Coverage | Missing operations or notes |
| --- | --- | --- | --- |
| Alerts: properties, view/filter/list logs, acknowledge, resolve, suppress/unsuppress, delete | — | Missing | Entire alert-management family. |
| Alert notes — create/list/view/update/delete | — | Missing | Entire alert-note family. |
| Assets: create/view/list/search/filter/update/delete/restore/permanently delete/move | `Get/New/Set/Remove/Restore-FreshServiceAsset` | Partial | Add permanent delete and move; `Get` provides search/filter forms, so validate them against current limits. |
| Asset assignment history | — | Missing | |
| Asset components — list/create/update | `Get-FreshServiceAsset -components` | Partial | Read only; add create/update component. |
| Asset requests/contracts/relationships — list associated requests/contracts; bulk create/delete relationships | `Get-FreshServiceAsset -requests/-contracts/-relationships`, `Get/New/Remove-FreshServiceRelationship`, `Get-FreshServiceRelationshipType` | Partial | Add assignment history and bulk relationship operations; check command semantics match asset-scoped versus account-wide relationship endpoints. |
| Asset types — create/view/list/update/delete/fields | `Get/New/Set/Remove-FreshServiceAssetType` | Partial | Add dedicated type-field retrieval/verify `Get -fields`. |
| Products — CRUD | `Get/New/Set/Remove-FreshServiceProduct` | Implemented | |
| Vendors — CRUD | `Get/New/Set/Remove-FreshServiceVendor` | Implemented | |
| Purchase orders — create/list/move/view/update/delete | `Get/New/Set/Remove-FreshServicePurchaseOrder` | Partial | Add move. |
| Software — create/update/view/list/licenses/delete/bulk delete | `Get/New/Set/Remove-FreshServiceSoftware` | Partial | Add license listing and bulk delete. |
| Software users — bulk add/view/move/list/bulk update/bulk remove | `Get/New/Set/Remove-FreshServiceSoftwareUser` | Partial | Add move and ensure bulk methods accept current API shapes. |
| Software installations — add/list/bulk remove | `Get/New/Remove-FreshServiceSoftwareInstallation` | Implemented | |
| Software relationships — list | — | Missing | |
| Contracts — types/fields/view/list/move/create/update/submit/approve/reject/assets/attachments | `Get-FreshServiceContract`, `Get-FreshServiceContractType`, `New/Set-FreshServiceContract` | Partial | Add move, reject, associated-assets list, and attachments list. Existing create/update expose submit/approve. |
| ITAM physical subtypes | — | Missing | Create/update/list/view/delete. |
| ITAM devices | — | Missing | Create/list/view/update/custom fields/delete. |
| ITAM cloud resources, relationships, cloud details, lifecycle events | — | Missing | Entire endpoint families. |

## Projects, solutions, and service catalog endpoints

| Endpoint family / official operations | Project command(s) | Coverage | Missing operations or notes |
| --- | --- | --- | --- |
| Legacy projects and legacy project tasks | — | Missing | The project’s commands target `/pm/projects` (NewGen), not the separately documented legacy API. Add only if legacy tenant support is a goal. |
| NewGen projects — create/update/view/list/delete/archive/restore/fields/templates/members/associations/delete attachment | `Get/New/Set/Remove/Restore-FreshServiceProject` | Partial | Basic CRUD/archive/restore and fields exist. Add templates, member management, associations, and attachment deletion. |
| NewGen project tasks — CRUD/filter/type-fields/types/priorities/statuses/versions/sprints/members/associations/notes/attachments | `Get/New/Set/Remove-FreshServiceProjectTask` | Partial | `Get` covers several lookup/filter endpoints. Add associations, notes, and attachment deletion. |
| Solution categories — create/update/view/list/delete/restore/permanent delete | `Get/New/Set/Remove-FreshServiceSolutionCategory` | Partial | Add restore and permanent delete. |
| Solution folders — create (including approval), update/view/subfolders/list/delete/restore/permanent delete | `Get/New/Set/Remove-FreshServiceSolutionFolder` | Partial | Add approval create, subfolders, restore, permanent delete. |
| Solution articles — create/secondary language/attachment/external URL/search/send for approval/publish/update/view/list/delete/restore/permanent delete/bulk restore | `Get/New/Set/Remove-FreshServiceSolutionArticle` | Partial | Add all listed specialist/lifecycle operations, especially restore and bulk restore. |
| Service-catalog items — view/list/search/create (visibility/shared fields)/update/delete | `Get-FreshServiceCatalogItem` | Partial | Read only. Add create/update/delete/search and visibility/shared-field inputs. |
| Service-catalog categories — list | `Get-FreshServiceCatalogCategory` | Implemented | |
| Service-catalog shared fields — list/search/create/update/delete/retrieve/archive/unarchive | — | Missing | Entire shared-field family. |
| Canned response folders/responses — list/view | `Get-FreshServiceCannedResponseFolder`, `Get-FreshServiceCannedResponse` | Implemented | The current v2 reference documents read operations only. |

## Employee workflow, incident, and collaboration endpoints

| Endpoint family / official operations | Project command(s) | Coverage | Missing operations or notes |
| --- | --- | --- | --- |
| Employee onboarding — form fields/create/view/list/onboarding tickets | `New-FreshServiceOnboardingRequest`, `Get-FreshServiceOnboardingRequest -fields/-tickets` | Implemented | |
| Employee offboarding — form fields/create/view/list/offboarding tickets | — | Missing | Entire endpoint family. |
| Journeys — published configs, initiator fields, create/view/filter/list/update/cancel/delete/activity | — | Missing | Entire endpoint family. |
| On-call management — schedules, shifts, overrides, calendars/export, who-is-on-call, escalation policies | — | Missing | Entire endpoint family. |
| Post-incident report templates — create/get/list/enable/set-primary/export/delete | — | Missing | Entire endpoint family. |
| Major-incident collaboration — trigger/retrieve email and Zoom meetings | — | Missing | Entire endpoint family. |
| Status page — incidents and updates, maintenance and updates, statuses, services/components, subscribers | — | Missing | Entire endpoint family. |
| Delegation — create/update/view/delete | — | Missing | Entire endpoint family. |
| Generic attachments — download; contract/purchase-order attachment download | — | Missing | Separate download endpoints are not exposed. |

## Target-scope decisions

The companion CSV classifies every endpoint family as `Add`, `Skip`, or `Conditional`. The committed surface favors the named PSU ticket, reporting, approval, fulfillment-read, and asset workloads rather than general endpoint completeness. Empty API coverage is not a defect unless an accepted workload requires it.

## Maintenance notes

- This matrix is a legacy comparison document, not generated code or an implementation queue. Update it when legacy evidence or the Freshservice API reference changes; update the companion CSV when target scope changes.
- **Browser verification:** on 2026-08-12, Playwright loaded the rendered API reference with its standard Freshservice (`itsm`) filter selected. The page exposed more than 600 documented operation labels and more than 400 rendered HTTP call blocks; the matrix's ticket move/attachment, alerts, CABs, offboarding, journeys, and on-call families were explicitly checked against those calls.
- The official documentation marks some operations as product-specific (`Freshservice`, `Business Teams`, `MSP`, or ITAM). Keep those feature gates visible in command help and tests.
- A command marked `Partial` should not be considered an endpoint-by-endpoint compatibility guarantee. Confirm URL shape, entitlement, pagination, rate cost, and request schema against the linked official reference before implementation.

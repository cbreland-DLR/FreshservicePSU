# Freshservice API v2 endpoint coverage matrix

**Snapshot:** 2026-08-12  
**Official reference:** <https://api.freshservice.com/v2/>  
**How to use this file:** This is legacy endpoint evidence, not the target product backlog. Per-endpoint-family coverage (`Implemented`/`Partial`/missing), review notes, and the authoritative `Add`/`Skip`/`Conditional` target-scope decision for every family are recorded row-by-row in [FRESHSERVICE_API_V2_ENDPOINT_COMPARISON.csv](FRESHSERVICE_API_V2_ENDPOINT_COMPARISON.csv); `SUPPORTED_COMMANDS.md` remains authoritative for the completed public surface.

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

## Per-endpoint coverage and target-scope decisions

The former per-endpoint coverage tables in this file duplicated the companion CSV column-for-column, minus the decision. The CSV is the single record: each row carries the endpoint family, its documented operations, the legacy command(s) covering it, the coverage verdict, the review note, and the explicit `Add`/`Skip`/`Conditional` decision. The committed surface favors the named PSU ticket, reporting, approval, fulfillment-read, and asset workloads rather than general endpoint completeness. Empty API coverage is not a defect unless an accepted workload requires it.

## Maintenance notes

- This matrix is a legacy comparison document, not generated code or an implementation queue. Update the companion CSV when legacy evidence, the Freshservice API reference, or target scope changes.
- **Browser verification:** on 2026-08-12, Playwright loaded the rendered API reference with its standard Freshservice (`itsm`) filter selected. The page exposed more than 600 documented operation labels and more than 400 rendered HTTP call blocks; the ticket move/attachment, alerts, CABs, offboarding, journeys, and on-call families were explicitly checked against those calls.
- The official documentation marks some operations as product-specific (`Freshservice`, `Business Teams`, `MSP`, or ITAM). Keep those feature gates visible in command help and tests.
- A command marked `Partial` in the CSV is not an endpoint-by-endpoint compatibility guarantee. Confirm URL shape, entitlement, pagination, rate cost, and request schema against the linked official reference before implementation.

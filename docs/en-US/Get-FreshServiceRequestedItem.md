# Get-FreshServiceRequestedItem

## SYNOPSIS

Gets requested items belonging to one Freshservice ticket.

## SYNTAX

```powershell
Get-FreshServiceRequestedItem -TicketId <Int64> [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/tickets/{ticket_id}/requested_items`. Does not place
or update a catalog request. `workspace_id` is not sent.

## OUTPUTS

### FreshservicePSU.RequestedItem

Contractual properties: `Id`, `TicketId`, `ServiceItemId`,
`Quantity`, `Stage`, `Loaned`, `CostPerRequest`, `IsParent`,
`CreatedAt`, `UpdatedAt`.

## EXAMPLES

```powershell
Get-FreshServiceRequestedItem -TicketId 1
```

# Get-FreshServiceTask

## SYNOPSIS

Gets ticket tasks belonging to one Freshservice ticket.

## SYNTAX

### ById

```powershell
Get-FreshServiceTask -TicketId <Int64> -Id <Int64> [<CommonParameters>]
```

### List (Default)

```powershell
Get-FreshServiceTask -TicketId <Int64> [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/tickets/{ticket_id}/tasks[/{id}]`. Ticket tasks only.
`workspace_id` is not sent.

## OUTPUTS

### FreshservicePSU.Task

Contractual properties: `Id`, `TicketId`, `Title`, `Status`,
`AgentId`, `GroupId`, `DueDate`, `ClosedAt`, `CreatedAt`, `UpdatedAt`.

## EXAMPLES

```powershell
Get-FreshServiceTask -TicketId 1
Get-FreshServiceTask -TicketId 1 -Id 1
```

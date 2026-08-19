# Get-FreshServiceRequestApproval

## SYNOPSIS

Gets approvals belonging to one Freshservice ticket.

## SYNTAX

### ById

```powershell
Get-FreshServiceRequestApproval -TicketId <Int64> -Id <Int64> [<CommonParameters>]
```

### List (Default)

```powershell
Get-FreshServiceRequestApproval -TicketId <Int64> [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/tickets/{ticket_id}/approvals[/{id}]`. Approval
actions are not supported. `workspace_id` is not sent.

## OUTPUTS

### FreshservicePSU.Approval

Contractual properties: `Id`, `TicketId`, `ApproverId`,
`ApproverName`, `UserId`, `UserName`, `ApprovalStatusId`,
`ApprovalStatusName`, `Level`, `CreatedAt`, `UpdatedAt`.

## EXAMPLES

```powershell
Get-FreshServiceRequestApproval -TicketId 20
Get-FreshServiceRequestApproval -TicketId 20 -Id 7163764235
```

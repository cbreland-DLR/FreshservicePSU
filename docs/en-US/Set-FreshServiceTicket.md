# Set-FreshServiceTicket

## SYNOPSIS

Updates ordinary properties on one Freshservice ticket.

## SYNTAX

```powershell
Set-FreshServiceTicket -TicketId <Int64> [-Subject <String>] [-Description <String>] [-RequesterId <Int64>] [-Status <Int32>] [-Priority <Int32>] [-Type <String>] [-Source <Int32>] [-Urgency <Int32>] [-Impact <Int32>] [-GroupId <Int64>] [-AgentId <Int64>] [-Category <String>] [-SubCategory <String>] [-ItemCategory <String>] [-Tags <String[]>] [-DepartmentId <Int64>] [-AssetDisplayId <Int64>] [-DueBy <DateTime>] [-FirstResponseDueBy <DateTime>] [-CustomFields <IDictionary>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION

Sends `PUT /api/v2/tickets/{id}` with only bound fields. Closing a
ticket is `-Status 5`. Restore, deletion, and workspace moves are out
of scope. `workspace_id` is not sent. Supports `-WhatIf`. Uses the
Enterprise Update Ticket limiter class (160).

## OUTPUTS

### FreshservicePSU.Ticket

Same output contract as `Get-FreshServiceTicket` (§6.6).

## EXAMPLES

```powershell
Set-FreshServiceTicket -TicketId 265 -Status 5 -WhatIf
Set-FreshServiceTicket -TicketId 265 -Priority 3 -AgentId $null
```

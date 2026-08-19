# New-FreshServiceTicket

## SYNOPSIS

Creates one Freshservice ticket.

## SYNTAX

### ByEmail (Default)

```powershell
New-FreshServiceTicket -Email <String> -Subject <String> -Description <String> [-Status <Int32>] [-Priority <Int32>] [-Type <String>] [-Source <Int32>] [-Urgency <Int32>] [-Impact <Int32>] [-GroupId <Int64>] [-AgentId <Int64>] [-Category <String>] [-SubCategory <String>] [-ItemCategory <String>] [-Tags <String[]>] [-DepartmentId <Int64>] [-AssetDisplayId <Int64>] [-DueBy <DateTime>] [-FirstResponseDueBy <DateTime>] [-CustomFields <IDictionary>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### ByRequesterId

```powershell
New-FreshServiceTicket -RequesterId <Int64> -Subject <String> -Description <String> [-Status <Int32>] [-Priority <Int32>] [-Type <String>] [-Source <Int32>] [-Urgency <Int32>] [-Impact <Int32>] [-GroupId <Int64>] [-AgentId <Int64>] [-Category <String>] [-SubCategory <String>] [-ItemCategory <String>] [-Tags <String[]>] [-DepartmentId <Int64>] [-AssetDisplayId <Int64>] [-DueBy <DateTime>] [-FirstResponseDueBy <DateTime>] [-CustomFields <IDictionary>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION

Sends `POST /api/v2/tickets` with only bound fields. Requires requester
email or ID, subject, and description. `workspace_id` is not sent.
Attachments and replies are out of scope. Supports `-WhatIf`. POST is
not retried after an uncertain delivery. Uses the Enterprise Create
Ticket limiter class (160).

## OUTPUTS

### FreshservicePSU.Ticket

Same output contract as `Get-FreshServiceTicket` (§6.6).

## EXAMPLES

```powershell
New-FreshServiceTicket -Email 'ada@contoso.com' -Subject 'VPN' -Description 'Cannot connect' -WhatIf
New-FreshServiceTicket -RequesterId 1000000675 -Subject 'VPN' -Description 'Cannot connect' -Priority 3 -GroupId 12
```

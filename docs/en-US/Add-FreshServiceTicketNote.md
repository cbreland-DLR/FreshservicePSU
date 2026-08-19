# Add-FreshServiceTicketNote

## SYNOPSIS

Adds a private or public note to one Freshservice ticket.

## SYNTAX

```powershell
Add-FreshServiceTicketNote -TicketId <Int64> -Body <String> [-Private <Boolean>] [-NotifyEmails <String[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION

Sends `POST /api/v2/tickets/{id}/notes`. Does not send a reply, close
the ticket, or attach files. `user_id` is not sent; authorship follows
the selected credential until Q7 evidence lands. `workspace_id` is not
sent. Supports `-WhatIf`. POST is not retried after an uncertain
delivery.

## OUTPUTS

### FreshservicePSU.TicketNote

Contractual properties: `Id`, `TicketId`, `Body`, `Private`,
`UserId`, `Incoming`, `CreatedAt`, `UpdatedAt`.

## EXAMPLES

```powershell
Add-FreshServiceTicketNote -TicketId 51 -Body 'Checked with the requester.' -Private $true
Add-FreshServiceTicketNote -TicketId 51 -Body 'Waiting on the vendor.' -NotifyEmails 'ada@contoso.com' -WhatIf
```

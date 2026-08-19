# Get-FreshServiceTicketActivity

## SYNOPSIS

Gets activity history for one Freshservice ticket.

## SYNTAX

```powershell
Get-FreshServiceTicketActivity -TicketId <Int64> [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/tickets/{id}/activities` and follows `next_page_url`
continuation tokens. Tokens are never written to output, errors, or
audit events. `workspace_id` is not sent.

## OUTPUTS

### FreshservicePSU.TicketActivity

Contractual properties: `TicketId`, `ActorId`, `ActorName`,
`Content`, `SubContents`, `CreatedAt`.

## EXAMPLES

```powershell
Get-FreshServiceTicketActivity -TicketId 152 -MaxRecords 60
```

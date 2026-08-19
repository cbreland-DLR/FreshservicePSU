# Search-FreshServiceTicket

## SYNOPSIS

Searches Freshservice tickets with a validated filter query.

## SYNTAX

```powershell
Search-FreshServiceTicket -Query <String> [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Executes `GET /api/v2/tickets/filter` for PSU reports and visualizations.
Tenant, stage, and credentials come from the trusted PSU execution context.
There is no public parameter for workspace, secret, identity, or base URI.
Bounded lists without a filter expression use `Get-FreshServiceTicket`.

The query is a Freshservice filter expression such as
`priority:4 OR status:2`. The module validates it, wraps it in the required
double quotes, and URL-encodes it. The query must:

- be non-empty and at most 512 characters
- contain at least one `field:value` (or `:>` / `:<`) condition
- have balanced parentheses and single quotes
- not contain double quotes or `workspace_id`

Paging uses the documented `page` parameter (default 30 results per page)
and the response `total` when present. A later-page failure throws
`FreshservicePSU.PartialResults`. Required Freshservice permission: view
tickets (`freshservice.tickets.view`).

## PARAMETERS

### -Query

Freshservice ticket filter expression. Surrounding double quotes are
optional and are stripped before validation.

### -PerPage

Page size, 1 through 100. Default 30.

### -MaxRecords

Stop after this many records. Default 1000.

## OUTPUTS

### FreshservicePSU.Ticket

Same output contract as `Get-FreshServiceTicket` (`SUPPORTED_COMMANDS.md`
§6.6).

## EXAMPLES

### High-priority open tickets

```powershell
Search-FreshServiceTicket -Query 'priority:3 AND status:2' -MaxRecords 100
```

### Streaming a report

```powershell
try {
    $tickets = @(Search-FreshServiceTicket -Query "status:2 OR status:3" -MaxRecords 200)
} catch {
    # Discard or reconcile $tickets if the error is PartialResults.
    throw
}
```

## NOTES

Does not accept `workspace_id`, embeds, or an empty query that would list
every ticket.

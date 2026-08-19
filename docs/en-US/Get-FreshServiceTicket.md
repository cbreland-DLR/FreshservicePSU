# Get-FreshServiceTicket

## SYNOPSIS

Gets one Freshservice ticket or a bounded ticket list.

## SYNTAX

### ById

```powershell
Get-FreshServiceTicket -TicketId <Int64> [-Include <String[]>] [<CommonParameters>]
```

### List (Default)

```powershell
Get-FreshServiceTicket [-RequesterId <Int64>] [-Email <String>] [-UpdatedSince <DateTime>] [-Filter <String>] [-Include <String[]>] [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads tickets for PSU detail pages, bounded lists, and reports. Tenant,
stage, and credentials come from the trusted PSU execution context. There
is no public parameter for workspace, secret, identity, or base URI.
Complex filter expressions belong on `Search-FreshServiceTicket`.

- Single-object read: `GET /api/v2/tickets/{id}`
- Bounded list: `GET /api/v2/tickets` with `per_page` 1-100, following
  `Link rel=next` until `MaxRecords` is reached (default 1000).
- List filters: `requester_id`, `email`, `updated_since`, and the
  predefined `filter` values `new_and_my_open`, `watching`, `spam`,
  `deleted`.

`-Include` accepts only `Requester`, `Stats`, and `Conversations`.
`Conversations` is valid only with `-TicketId`. Each embed costs additional
API credits: +1 on a single-ticket read, +2 on a list read. Requested
items, tasks, approvals, and activity have dedicated commands and are not
embeds.

A later-page failure throws `FreshservicePSU.PartialResults` after some
records may already have been emitted. Required Freshservice permission:
view tickets (`freshservice.tickets.view`).

## PARAMETERS

### -TicketId

Freshservice ticket identifier.

### -RequesterId

Limit a list to tickets for this requester.

### -Email

Limit a list to tickets for this requester email.

### -UpdatedSince

Limit a list to tickets with activity at or after this timestamp.

### -Filter

Predefined Freshservice list filter.

### -Include

Opt-in embeds: `Requester`, `Stats`, `Conversations`.

### -PerPage

Page size, 1 through 100. Default 100.

### -MaxRecords

Stop after this many list records. Default 1000.

## OUTPUTS

### FreshservicePSU.Ticket

Contractual properties: `Id`, `Subject`, `Status`, `Priority`,
`Type`, `RequesterId`, `ResponderId`, `GroupId`, `DepartmentId`,
`CreatedAt`, `UpdatedAt`, `DueBy`, `FirstResponseDueBy`.
`Requester`, `Stats`, and `Conversations` appear only when requested and
are not compatibility guarantees.

## EXAMPLES

### PSU ticket detail

```powershell
Get-FreshServiceTicket -TicketId 266
```

### Detail with embeds

```powershell
Get-FreshServiceTicket -TicketId 266 -Include Requester, Stats
```

### Bounded recent list

```powershell
try {
    $tickets = @(Get-FreshServiceTicket -UpdatedSince (Get-Date).AddDays(-1) -MaxRecords 50)
} catch {
    # Discard or reconcile $tickets if the error is PartialResults.
    throw
}
```

## NOTES

Does not create, update, close, or search with a Freshservice filter
expression. Does not accept `workspace_id`.

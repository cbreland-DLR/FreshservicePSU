# Get-FreshServiceTicketField

## SYNOPSIS

Gets Freshservice ticket form field definitions.

## SYNTAX

### List (Default)

```powershell
Get-FreshServiceTicketField [-MaxRecords <Int32>] [<CommonParameters>]
```

### ById

```powershell
Get-FreshServiceTicketField -Id <Int64> [<CommonParameters>]
```

### ByName

```powershell
Get-FreshServiceTicketField -Name <String> [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/ticket_form_fields` for PSU dynamic forms and for
resolving stored values to display labels. Tenant, stage, and credentials
come from the trusted PSU execution context. There is no public parameter
for workspace, secret, identity, or base URI.

The vendor documents a list endpoint only. `-Id` and `-Name` select one
field from that list after the request. Ticket-field data is cache-eligible;
the shared reference-data cache is not wired yet, so every call hits
Freshservice.

Required Freshservice permission: manage/view ticket fields
(`freshservice.tickets.fields.manage`).

## PARAMETERS

### -Id

Freshservice ticket field identifier.

### -Name

API field name (`requester`, `status`, custom field name).

### -MaxRecords

Stop after this many list records. Default 1000.

## OUTPUTS

### FreshservicePSU.TicketField

Contractual properties: `Id`, `Name`, `Label`, `FieldType`,
`Required`, `DefaultField`, `Choices`, `CreatedAt`, `UpdatedAt`.
`Description` and `NestedFields` may pass through and are not contractual.
`workspace_id` is not part of the public contract.

## EXAMPLES

### Build a PSU ticket form

```powershell
Get-FreshServiceTicketField
```

### Resolve the status field choices

```powershell
Get-FreshServiceTicketField -Name status
```

## NOTES

Does not create or update fields. Does not accept `workspace_id`.

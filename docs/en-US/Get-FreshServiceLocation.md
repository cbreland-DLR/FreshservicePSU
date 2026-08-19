# Get-FreshServiceLocation

## SYNOPSIS

Gets one Freshservice location or a bounded list of locations.

## SYNTAX

### ById

```powershell
Get-FreshServiceLocation -Id <Int64> [<CommonParameters>]
```

### List (Default)

```powershell
Get-FreshServiceLocation [-Name <String>] [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads location records for PSU form choices and report dimensions. Tenant,
stage, and credentials come from the trusted PSU execution context. There is
no public parameter for workspace, secret, identity, or base URI.

- Single-object read: `GET /api/v2/locations/{id}`
- Bounded list: `GET /api/v2/locations` with `per_page` 1-100, following
  `Link rel=next` until `MaxRecords` is reached (default 1000).
- Optional `-Name` sends the documented filter `query=name:'...'`.

Location data is cache-eligible. The shared reference-data cache is not
wired yet; every call hits Freshservice. A later-page failure throws
`FreshservicePSU.PartialResults` after some records may already have been
emitted. Required Freshservice permission: view locations
(`freshservice.locations.view`).

## PARAMETERS

### -Id

Freshservice location identifier.

### -Name

Location name passed to the filter query. Not combined with `-Id`.

### -PerPage

Page size, 1 through 100. Default 100.

### -MaxRecords

Stop after this many list records. Default 1000.

## OUTPUTS

### FreshservicePSU.Location

Contractual properties: `Id`, `Name`, `ParentLocationId`,
`PrimaryContactId`, `CreatedAt`, `UpdatedAt`. Additional vendor fields such
as `Address`, `ContactName`, `Email`, `Phone`, and `Primary` may be present
and are not compatibility guarantees.

## EXAMPLES

### PSU form lookup

```powershell
Get-FreshServiceLocation -Id 15
```

### Bounded name filter for a choice list

```powershell
Get-FreshServiceLocation -Name 'HQ' -MaxRecords 20
```

### Streaming a list

```powershell
try {
    $locations = @(Get-FreshServiceLocation -MaxRecords 200)
} catch {
    # Discard or reconcile $locations if the error is PartialResults.
    throw
}
```

## NOTES

Does not create, update, or delete locations. Does not accept `workspace_id`.

# Get-FreshServiceBusinessHour

## SYNOPSIS

Gets one Freshservice business-hours definition or a bounded list.

## SYNTAX

### ById

```powershell
Get-FreshServiceBusinessHour -Id <Int64> [<CommonParameters>]
```

### List (Default)

```powershell
Get-FreshServiceBusinessHour [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/business_hours` and
`GET /api/v2/business_hours/{id}`. Configuration writes are not
supported. `workspace_id` is not sent. `require_feature` or HTTP 405
becomes `FreshservicePSU.BusinessHour.Unavailable`.

## OUTPUTS

### FreshservicePSU.BusinessHour

Contractual properties: `Id`, `Name`, `Description`, `IsDefault`,
`TimeZone`, `CreatedAt`, `UpdatedAt`.

## EXAMPLES

```powershell
Get-FreshServiceBusinessHour -Id 1
Get-FreshServiceBusinessHour
```

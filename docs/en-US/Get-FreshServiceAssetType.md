# Get-FreshServiceAssetType

## SYNOPSIS

Gets one Freshservice asset type or a bounded asset-type list.

## SYNTAX

### ById

```powershell
Get-FreshServiceAssetType -Id <Int64> [<CommonParameters>]
```

### List (Default)

```powershell
Get-FreshServiceAssetType [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/asset_types` and `GET /api/v2/asset_types/{id}` for
PSU asset forms, filters, and validation. Asset-type fields are a
different resource and are not selected through a mode switch.
`workspace_id` is not sent. Eligible for the reference cache; the cache
is not yet wired.

## OUTPUTS

### FreshservicePSU.AssetType

Contractual properties: `Id`, `Name`, `ParentAssetTypeId`,
`Description`, `Visible`, `CreatedAt`, `UpdatedAt`.

## EXAMPLES

```powershell
Get-FreshServiceAssetType -Id 50
Get-FreshServiceAssetType -MaxRecords 50
```

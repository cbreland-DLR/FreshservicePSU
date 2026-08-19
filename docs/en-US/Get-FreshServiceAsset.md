# Get-FreshServiceAsset

## SYNOPSIS

Gets one Freshservice asset or a bounded filtered asset list.

## SYNTAX

### DisplayId

```powershell
Get-FreshServiceAsset -DisplayId <Int64> [<CommonParameters>]
```

### AssetTag

```powershell
Get-FreshServiceAsset -AssetTag <String> [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

### SerialNumber

```powershell
Get-FreshServiceAsset -SerialNumber <String> [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

### Filter (Default)

```powershell
Get-FreshServiceAsset -Filter <String> [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/assets/{display_id}` and `GET /api/v2/assets?filter=`
for PSU asset pages, automations, and reporting. `-DisplayId` is a
single-object read. `-AssetTag` and `-SerialNumber` are exact lookups.
`-Filter` is a validated vendor filter. There is no unbounded list and
no path into components, requests, contracts, or relationships.
`workspace_id` is not sent.

Filter operations use numbered paging (`page`/`total`, default page
size 30) and the Enterprise List All Assets limiter class (140). Asset
records are not implicitly cacheable.

## OUTPUTS

### FreshservicePSU.Asset

Contractual properties: `Id`, `DisplayId`, `Name`, `AssetTag`,
`AssetTypeId`, `UsageType`, `Impact`, `LocationId`, `DepartmentId`,
`AgentId`, `UserId`, `GroupId`, `AssignedOn`, `CreatedAt`, `UpdatedAt`.

## EXAMPLES

```powershell
Get-FreshServiceAsset -DisplayId 11
Get-FreshServiceAsset -AssetTag 'ASSET-9'
Get-FreshServiceAsset -SerialNumber 'SW12131133'
Get-FreshServiceAsset -Filter "asset_state:'IN STOCK' AND location_id:3" -MaxRecords 50
```

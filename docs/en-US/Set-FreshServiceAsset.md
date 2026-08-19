# Set-FreshServiceAsset

## SYNOPSIS

Updates ordinary properties on one Freshservice asset.

## SYNTAX

```powershell
Set-FreshServiceAsset -DisplayId <Int64> [-AssetTag <String>] [-Name <String>] [-Description <String>] [-UsageType <String>] [-Impact <String>] [-LocationId <Int64>] [-DepartmentId <Int64>] [-AgentId <Int64>] [-UserId <Int64>] [-GroupId <Int64>] [-AssignedOn <DateTime>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION

Sends `PUT /api/v2/assets/{display_id}` with only the fields the caller
bound. Supports `-WhatIf` and `-Confirm`. Does not create, delete,
restore, permanently delete, move, or change the asset type.
`workspace_id` is not sent. Type-specific fields are not accepted until
`Get-FreshServiceAssetType` can allowlist them.

Uses the Enterprise Update Asset limiter class (160).

## OUTPUTS

### FreshservicePSU.Asset

Same output contract as `Get-FreshServiceAsset` (§6.12).

## EXAMPLES

```powershell
Set-FreshServiceAsset -DisplayId 11 -Name 'Macbook Pro 2' -WhatIf
Set-FreshServiceAsset -DisplayId 11 -LocationId 3 -AgentId $null
```

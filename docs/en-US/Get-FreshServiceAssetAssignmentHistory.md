# Get-FreshServiceAssetAssignmentHistory

## SYNOPSIS

Gets assignment history for one Freshservice asset.

## SYNTAX

```powershell
Get-FreshServiceAssetAssignmentHistory -DisplayId <Int64> [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/assets/{display_id}/assignment-history` for assignment
audit and reporting. `workspace_id` is not sent.

A missing or unauthorized asset stays a not-found or access error. When
the tenant lacks the feature (`require_feature` or HTTP 405), the
command throws `FreshservicePSU.Asset.AssignmentHistoryUnavailable`
instead of returning an empty list. Live tenant availability remains
the Q9 evidence item.

## OUTPUTS

### FreshservicePSU.AssetAssignmentHistory

Contractual properties: `Id`, `DisplayId`, `UserId`, `UserName`,
`AssignedOn`, `AssignedBy`, `AssignedByName`, `UnassignedBy`,
`UnassignedByName`, `UnassignedOn`, `CreatedAt`, `UpdatedAt`.

## EXAMPLES

```powershell
Get-FreshServiceAssetAssignmentHistory -DisplayId 8
Get-FreshServiceAssetAssignmentHistory -DisplayId 8 -MaxRecords 20
```

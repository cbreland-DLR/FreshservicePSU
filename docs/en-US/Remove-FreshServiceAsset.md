# Remove-FreshServiceAsset

## SYNOPSIS

Soft-deletes one Freshservice asset.

## SYNTAX

```powershell
Remove-FreshServiceAsset -DisplayId <Int64> [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION

Sends `DELETE /api/v2/assets/{display_id}`. This is the vendor trash
operation. Restore, permanent delete, and workspace moves are out of
scope. `workspace_id` is not sent.

Supports `-WhatIf` and `-Confirm`. ConfirmImpact is High. Success
returns HTTP 204 and writes no pipeline output.

## EXAMPLES

```powershell
Remove-FreshServiceAsset -DisplayId 11 -WhatIf
Remove-FreshServiceAsset -DisplayId 11
```

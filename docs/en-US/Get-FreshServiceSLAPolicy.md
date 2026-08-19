# Get-FreshServiceSLAPolicy

## SYNOPSIS

Gets Freshservice SLA policy definitions.

## SYNTAX

```powershell
Get-FreshServiceSLAPolicy [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/sla_policies`. `workspace_id` is not sent.
`require_feature` or HTTP 405 becomes
`FreshservicePSU.SLAPolicy.Unavailable`.

## OUTPUTS

### FreshservicePSU.SLAPolicy

Contractual properties: `Id`, `Name`, `Position`, `IsDefault`,
`Active`, `Deleted`, `Description`.

## EXAMPLES

```powershell
Get-FreshServiceSLAPolicy
```

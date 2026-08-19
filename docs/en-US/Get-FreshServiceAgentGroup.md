# Get-FreshServiceAgentGroup

## SYNOPSIS

Gets one Freshservice agent group or a bounded group list.

## SYNTAX

### ById

```powershell
Get-FreshServiceAgentGroup -Id <Int64> [<CommonParameters>]
```

### List (Default)

```powershell
Get-FreshServiceAgentGroup [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/groups` and `GET /api/v2/groups/{id}` for PSU
assignment choices and report dimensions. Tenant, stage, and credentials
come from the trusted PSU execution context. `workspace_id` is not sent.

Does not create or update groups or change membership. Required
permission: view agent groups.

## OUTPUTS

### FreshservicePSU.AgentGroup

Contractual properties: `Id`, `Name`, `Description`, `Restricted`,
`EscalateTo`, `BusinessHoursId`, `CreatedAt`, `UpdatedAt`.

## EXAMPLES

```powershell
Get-FreshServiceAgentGroup -Id 1
Get-FreshServiceAgentGroup -MaxRecords 50
```

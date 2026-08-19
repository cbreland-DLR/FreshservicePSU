# Get-FreshServiceAgent

## SYNOPSIS

Gets one Freshservice agent or a bounded agent list.

## SYNTAX

### ById

```powershell
Get-FreshServiceAgent -Id <Int64> [<CommonParameters>]
```

### List (Default)

```powershell
Get-FreshServiceAgent [-Email <String>] [-Active <Boolean>] [-State <String>] [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/agents` and `GET /api/v2/agents/{id}` for PSU assignee
labels and reports. List filters are the documented `email`, `active`,
and `state` query parameters. Does not deactivate, forget, or convert
agents. `workspace_id` is not sent.

List operations use the Enterprise List All Agents limiter class (140).

## OUTPUTS

### FreshservicePSU.Agent

Contractual properties: `Id`, `FirstName`, `LastName`, `Email`,
`Active`, `JobTitle`, `DepartmentIds`, `LocationId`, `ReportingManagerId`.

## EXAMPLES

```powershell
Get-FreshServiceAgent -Id 1434
Get-FreshServiceAgent -Email 'ada@contoso.com'
Get-FreshServiceAgent -Active $true -State fulltime -MaxRecords 50
```

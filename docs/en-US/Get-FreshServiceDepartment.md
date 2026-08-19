# Get-FreshServiceDepartment

## SYNOPSIS

Gets one Freshservice department or a bounded department list.

## SYNTAX

### ById

```powershell
Get-FreshServiceDepartment -Id <Int64> [<CommonParameters>]
```

### List (Default)

```powershell
Get-FreshServiceDepartment [-Name <String>] [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/departments` and `GET /api/v2/departments/{id}` for
PSU form choices and report dimensions. `-Name` sends the documented
filter `query="name:'...'`. `workspace_id` is not sent.

## OUTPUTS

### FreshservicePSU.Department

Contractual properties: `Id`, `Name`, `Description`, `HeadUserId`,
`PrimeUserId`, `CreatedAt`, `UpdatedAt`.

## EXAMPLES

```powershell
Get-FreshServiceDepartment -Id 1
Get-FreshServiceDepartment -Name 'Sales'
```

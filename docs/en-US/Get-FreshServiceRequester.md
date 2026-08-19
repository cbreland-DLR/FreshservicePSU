# Get-FreshServiceRequester

## SYNOPSIS

Gets one Freshservice requester or a bounded requester list.

## SYNTAX

### ById

```powershell
Get-FreshServiceRequester -Id <Int64> [<CommonParameters>]
```

### List (Default)

```powershell
Get-FreshServiceRequester [-Email <String>] [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/requesters` and `GET /api/v2/requesters/{id}` for PSU
requester-level reporting and enrichment. List filter is the documented
`email` query parameter. Does not create, update, deactivate, forget,
merge, or convert requesters. `workspace_id` and `include_agents` are
not sent.

Requester records are not implicitly cacheable. List operations use the
Enterprise List All Requesters limiter class (140).

## OUTPUTS

### FreshservicePSU.Requester

Contractual properties: `Id`, `FirstName`, `LastName`, `Email`,
`Active`, `JobTitle`, `DepartmentIds`, `LocationId`,
`ReportingManagerId`.

## EXAMPLES

```powershell
Get-FreshServiceRequester -Id 777
Get-FreshServiceRequester -Email 'ada@contoso.com'
Get-FreshServiceRequester -MaxRecords 50
```

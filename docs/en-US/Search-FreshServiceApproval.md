# Search-FreshServiceApproval

## SYNOPSIS

Searches Freshservice ticket approvals across tickets.

## SYNTAX

```powershell
Search-FreshServiceApproval [-ApproverId <Int64>] [-Status <String>] [-ParentId <Int64>] [-DelegateeId <Int64>] [-Level <Int32>] [-PerPage <Int32>] [-MaxRecords <Int32>] [<CommonParameters>]
```

## DESCRIPTION

Reads `GET /api/v2/approvals` with `parent=ticket` and at least one of
`-ApproverId`, `-Status`, `-ParentId`, or `-DelegateeId`. Change
approvals are out of scope. `workspace_id` is not sent.

Uses numbered paging (default page size 30). `require_feature` or HTTP
405 becomes `FreshservicePSU.Approval.SearchUnavailable`. Live Q8
evidence still decides whether this tenant keeps the command.

## OUTPUTS

### FreshservicePSU.Approval

Same output contract as `Get-FreshServiceRequestApproval` (§6.17).

## EXAMPLES

```powershell
Search-FreshServiceApproval -Status requested -ApproverId 123
```

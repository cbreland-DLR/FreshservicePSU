function Search-FreshServiceApproval {
    <#
    .SYNOPSIS
        Searches Freshservice ticket approvals across tickets.

    .DESCRIPTION
        Reads GET /approvals with parent=ticket and at least one of
        approver, status, parent ID, or delegatee. Tenant, stage, and
        credentials come from the trusted PSU execution context.
        workspace_id is not sent. Change approvals are out of scope.

        When the tenant lacks the endpoint (require_feature or HTTP 405),
        the command throws FreshservicePSU.Approval.SearchUnavailable
        instead of returning an empty list. Results use numbered paging.

    .PARAMETER ApproverId
        Filter by approver user ID.

    .PARAMETER Status
        Filter by approval status name, for example requested.

    .PARAMETER ParentId
        Filter by parent ticket ID.

    .PARAMETER DelegateeId
        Filter by delegatee user ID.

    .PARAMETER Level
        Optional approval level.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 30, matching the endpoint.

    .PARAMETER MaxRecords
        Maximum records to emit. Default 1000.

    .EXAMPLE
        Search-FreshServiceApproval -Status requested -ApproverId 123

        Streams requested ticket approvals for approver 123.

    .OUTPUTS
        FreshservicePSU.Approval
    #>
    [CmdletBinding()]
    [OutputType('FreshservicePSU.Approval')]
    param(
        [ValidateRange(1, [long]::MaxValue)]
        [long]$ApproverId,

        [ValidateNotNullOrEmpty()]
        [string]$Status,

        [ValidateRange(1, [long]::MaxValue)]
        [long]$ParentId,

        [ValidateRange(1, [long]::MaxValue)]
        [long]$DelegateeId,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$Level,

        [ValidateRange(1, 100)]
        [int]$PerPage = 30,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000
    )

    $hasRequiredFilter = @(
        'ApproverId', 'Status', 'ParentId', 'DelegateeId'
    ).Where({ $PSBoundParameters.ContainsKey($_) }).Count -gt 0
    if (-not $hasRequiredFilter) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Approval.FilterRequired' -Message 'Search-FreshServiceApproval requires at least one of -ApproverId, -Status, -ParentId, or -DelegateeId.' -Category InvalidArgument)
    }

    $query = @{ parent = 'ticket' }
    if ($PSBoundParameters.ContainsKey('ApproverId')) {
        $query['approver_id'] = $ApproverId
    }
    if ($PSBoundParameters.ContainsKey('Status')) {
        $query['status'] = $Status
    }
    if ($PSBoundParameters.ContainsKey('ParentId')) {
        $query['parent_id'] = $ParentId
    }
    if ($PSBoundParameters.ContainsKey('DelegateeId')) {
        $query['delegatee_id'] = $DelegateeId
    }
    if ($PSBoundParameters.ContainsKey('Level')) {
        $query['level'] = $Level
    }

    $context = Get-FsuExecutionContext
    try {
        Invoke-FsuNumberedPagedRequest `
            -Context $context `
            -PathSegments @('approvals') `
            -QueryParameters $query `
            -EnvelopeProperty 'approvals' `
            -PSTypeName 'FreshservicePSU.Approval' `
            -PerPage $PerPage `
            -MaxRecords $MaxRecords `
            -Operation 'Search-FreshServiceApproval' |
            ConvertTo-FsuApproval
    } catch {
        $mapped = ConvertTo-FsuFeatureUnavailableError -InputObject $_ -ErrorId 'FreshservicePSU.Approval.SearchUnavailable' -Message 'Cross-ticket approval search is not available on this tenant.' -CorrelationId ([string]$context.CorrelationId)
        if ($mapped) {
            throw $mapped
        }
        throw
    }
}


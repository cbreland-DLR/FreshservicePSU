function Get-FreshServiceAssetAssignmentHistory {
    <#
    .SYNOPSIS
        Gets assignment history for one Freshservice asset.

    .DESCRIPTION
        Reads GET /assets/{display_id}/assignment-history for assignment
        audit and reporting. Tenant, stage, and credentials come from
        the trusted PSU execution context. workspace_id is not sent.

        A missing or unauthorized asset stays a not-found or access
        error. When the tenant lacks the assignment-history feature
        (require_feature or HTTP 405), the command throws
        FreshservicePSU.Asset.AssignmentHistoryUnavailable instead of
        returning an empty list.

    .PARAMETER DisplayId
        Freshservice asset display ID used in the asset URL.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 100.

    .PARAMETER MaxRecords
        Maximum history records to emit. Default 1000.

    .EXAMPLE
        Get-FreshServiceAssetAssignmentHistory -DisplayId 8

        Returns assignment events for asset display ID 8.

    .OUTPUTS
        FreshservicePSU.AssetAssignmentHistory
    #>
    [CmdletBinding()]
    [OutputType('FreshservicePSU.AssetAssignmentHistory')]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$DisplayId,

        [ValidateRange(1, 100)]
        [int]$PerPage = 100,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000
    )

    $context = Get-FsuExecutionContext

    try {
        Invoke-FsuPagedRequest `
            -Context $context `
            -PathSegments @('assets', [string]$DisplayId, 'assignment-history') `
            -EnvelopeProperty 'assignment_history' `
            -PSTypeName 'FreshservicePSU.AssetAssignmentHistory' `
            -PerPage $PerPage `
            -MaxRecords $MaxRecords `
            -Operation 'Get-FreshServiceAssetAssignmentHistory' `
            -ResourceId ([string]$DisplayId) |
            ConvertTo-FsuAssetAssignmentHistory -DisplayId $DisplayId
    } catch {
        $errorId = [string]$_.FullyQualifiedErrorId
        if ($errorId -match 'RequireFeature|MethodNotAllowed') {
            throw (New-FsuErrorRecord `
                    -ErrorId 'FreshservicePSU.Asset.AssignmentHistoryUnavailable' `
                    -Message 'Asset assignment history is not available on this tenant.' `
                    -Category ResourceUnavailable `
                    -CorrelationId ([string]$context.CorrelationId) `
                    -StatusCode $(if ($_.Exception.Data.Contains('StatusCode')) { $_.Exception.Data['StatusCode'] } else { $null }))
        }
        throw
    }
}

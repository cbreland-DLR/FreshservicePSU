function Get-FreshServiceSLAPolicy {
    <#
    .SYNOPSIS
        Gets Freshservice SLA policy definitions.

    .DESCRIPTION
        Reads GET /sla_policies for SLA configuration reports.
        Tenant, stage, and credentials come from the trusted PSU
        execution context. workspace_id is not sent. Ordinary SLA
        performance reporting uses ticket dates and statistics.

        When the tenant lacks the endpoint (require_feature or HTTP 405),
        the command throws FreshservicePSU.SLAPolicy.Unavailable instead
        of returning an empty list.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 100.

    .PARAMETER MaxRecords
        Maximum records to emit. Default 1000.

    .EXAMPLE
        Get-FreshServiceSLAPolicy

        Returns SLA policy definitions for a configuration report.

    .OUTPUTS
        FreshservicePSU.SLAPolicy
    #>
    [CmdletBinding()]
    [OutputType('FreshservicePSU.SLAPolicy')]
    param(
        [ValidateRange(1, 100)]
        [int]$PerPage = 100,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000
    )

    $context = Get-FsuExecutionContext
    try {
        Invoke-FsuPagedRequest `
            -Context $context `
            -PathSegments @('sla_policies') `
            -EnvelopeProperty 'sla_policies' `
            -PSTypeName 'FreshservicePSU.SLAPolicy' `
            -PerPage $PerPage `
            -MaxRecords $MaxRecords `
            -Operation 'Get-FreshServiceSLAPolicy' |
            ConvertTo-FsuSLAPolicy
    } catch {
        $mapped = ConvertTo-FsuFeatureUnavailableError -InputObject $_ -ErrorId 'FreshservicePSU.SLAPolicy.Unavailable' -Message 'SLA policy reads are not available on this tenant.' -CorrelationId ([string]$context.CorrelationId)
        if ($mapped) {
            throw $mapped
        }
        throw
    }
}

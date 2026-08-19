function Get-FreshServiceBusinessHour {
    <#
    .SYNOPSIS
        Gets one Freshservice business-hours definition or a bounded list.

    .DESCRIPTION
        Reads GET /business_hours[/{id}] for policy reports. Tenant,
        stage, and credentials come from the trusted PSU execution
        context. Configuration writes are not supported. workspace_id
        is not sent.

        When the tenant lacks the endpoint (require_feature or HTTP 405),
        the command throws FreshservicePSU.BusinessHour.Unavailable
        instead of returning an empty list.

    .PARAMETER Id
        Freshservice business-hours ID.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 100.

    .PARAMETER MaxRecords
        Maximum records to emit for a list. Default 1000.

    .EXAMPLE
        Get-FreshServiceBusinessHour -Id 1

        Returns the default business calendar.

    .OUTPUTS
        FreshservicePSU.BusinessHour
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('FreshservicePSU.BusinessHour')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$Id,

        [Parameter(ParameterSetName = 'List')]
        [ValidateRange(1, 100)]
        [int]$PerPage = 100,

        [Parameter(ParameterSetName = 'List')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000
    )

    $context = Get-FsuExecutionContext
    $common = @{
        Context = $context
        Operation = 'Get-FreshServiceBusinessHour'
    }

    try {
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $envelope = Invoke-FsuRequest @common `
                -Method GET `
                -PathSegments @('business_hours', [string]$Id) `
                -ResourceId ([string]$Id)
            $payload = Get-FsuSingularEnvelopePayload -Body $envelope.Body -PrimaryName 'business_hour' -AlternateName 'business_hours' -CorrelationId ([string]$context.CorrelationId)
            ConvertTo-FsuBusinessHour -InputObject $payload
            return
        }

        Invoke-FsuPagedRequest @common `
            -PathSegments @('business_hours') `
            -EnvelopeProperty 'business_hours' `
            -PSTypeName 'FreshservicePSU.BusinessHour' `
            -PerPage $PerPage `
            -MaxRecords $MaxRecords |
            ConvertTo-FsuBusinessHour
    } catch {
        $mapped = ConvertTo-FsuFeatureUnavailableError -InputObject $_ -ErrorId 'FreshservicePSU.BusinessHour.Unavailable' -Message 'Business-hours reads are not available on this tenant.' -CorrelationId ([string]$context.CorrelationId)
        if ($mapped) {
            throw $mapped
        }
        throw
    }
}

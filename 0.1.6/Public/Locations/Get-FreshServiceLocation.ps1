function Get-FreshServiceLocation {
    <#
    .SYNOPSIS
        Gets one Freshservice location or a bounded list of locations.

    .DESCRIPTION
        Reads location records used as PSU form choices and report
        dimensions. Tenant, stage, and credentials come from the trusted
        PSU execution context. This command does not accept workspace,
        secret, or identity parameters.

        A single -Id call uses GET /locations/{id}. A list call uses
        GET /locations, optionally filtered by -Name via the documented
        query=name:'...' form, and streams pages until MaxRecords is
        reached. Location reference data is cache-eligible; the shared
        reference cache is not yet wired (Q15 / Phase 4 remainder).

    .PARAMETER Id
        Freshservice location ID.

    .PARAMETER Name
        Exact location name filter using GET /locations?query="name:'...'".

    .PARAMETER PerPage
        Page size from 1 to 100. Default 100.

    .PARAMETER MaxRecords
        Maximum records to emit for a list. Default 1000.

    .EXAMPLE
        Get-FreshServiceLocation -Id 15

        Returns one location for a PSU form that already has the ID.

    .EXAMPLE
        Get-FreshServiceLocation -Name 'HQ' -MaxRecords 20

        Streams matching locations for a choice list, stopping at 20 records.

    .OUTPUTS
        FreshservicePSU.Location
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('FreshservicePSU.Location')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$Id,

        [Parameter(ParameterSetName = 'List')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

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
        Operation = 'Get-FreshServiceLocation'
    }

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $common['ResourceId'] = [string]$Id
        $envelope = Invoke-FsuRequest @common `
            -Method GET `
            -PathSegments @('locations', [string]$Id)
        $payload = Get-FsuLocationEnvelopePayload -Body $envelope.Body -CorrelationId ([string]$context.CorrelationId)
        ConvertTo-FsuLocation -InputObject $payload
        return
    }

    $query = @{}
    if ($PSBoundParameters.ContainsKey('Name')) {
        $query['query'] = ("name:'{0}'" -f ($Name -replace "'", "''"))
    }

    Invoke-FsuPagedRequest @common `
        -PathSegments @('locations') `
        -QueryParameters $query `
        -EnvelopeProperty 'locations' `
        -PSTypeName 'FreshservicePSU.Location' `
        -PerPage $PerPage `
        -MaxRecords $MaxRecords |
        ConvertTo-FsuLocation
}

function Get-FreshServiceRequester {
    <#
    .SYNOPSIS
        Gets one Freshservice requester or a bounded requester list.

    .DESCRIPTION
        Reads requesters for PSU requester-level reports and enrichment.
        Tenant, stage, and credentials come from the trusted PSU
        execution context. Does not create, update, deactivate, forget,
        merge, or convert requesters. workspace_id and include_agents
        are not sent.

        -Id uses GET /requesters/{id}. A list call uses GET /requesters
        with an optional email filter. Requester records are not
        implicitly cacheable.

    .PARAMETER Id
        Freshservice requester ID.

    .PARAMETER Email
        Limit a list to this requester primary email.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 100.

    .PARAMETER MaxRecords
        Maximum records to emit for a list. Default 1000.

    .EXAMPLE
        Get-FreshServiceRequester -Email 'ada@contoso.com'

        Returns the matching requester for report enrichment.

    .OUTPUTS
        FreshservicePSU.Requester
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('FreshservicePSU.Requester')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$Id,

        [Parameter(ParameterSetName = 'List')]
        [ValidateNotNullOrEmpty()]
        [string]$Email,

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
        Operation = 'Get-FreshServiceRequester'
    }

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $raw = Invoke-FsuRequest @common `
            -Method GET `
            -PathSegments @('requesters', [string]$Id) `
            -EnvelopeProperty 'requester' `
            -PSTypeName 'FreshservicePSU.Requester' `
            -ResourceId ([string]$Id)
        ConvertTo-FsuRequester -InputObject $raw
        return
    }

    $query = @{}
    if ($PSBoundParameters.ContainsKey('Email')) {
        $query['email'] = $Email
    }

    Invoke-FsuPagedRequest @common `
        -PathSegments @('requesters') `
        -QueryParameters $query `
        -EnvelopeProperty 'requesters' `
        -PSTypeName 'FreshservicePSU.Requester' `
        -PerPage $PerPage `
        -MaxRecords $MaxRecords |
        ConvertTo-FsuRequester
}

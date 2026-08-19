function Get-FreshServiceDepartment {
    <#
    .SYNOPSIS
        Gets one Freshservice department or a bounded department list.

    .DESCRIPTION
        Reads departments for PSU form choices and report dimensions.
        Tenant, stage, and credentials come from the trusted PSU
        execution context. workspace_id is not sent.

        -Id uses GET /departments/{id}. A list call uses GET /departments,
        optionally filtered by -Name via query="name:'...'", and streams
        pages until MaxRecords is reached. Department data is
        cache-eligible; the shared reference cache is not yet wired.

    .PARAMETER Id
        Freshservice department ID.

    .PARAMETER Name
        Exact department name filter.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 100.

    .PARAMETER MaxRecords
        Maximum records to emit for a list. Default 1000.

    .EXAMPLE
        Get-FreshServiceDepartment -Name 'Sales'

        Returns the Sales department for a form choice list.

    .OUTPUTS
        FreshservicePSU.Department
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('FreshservicePSU.Department')]
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
        Operation = 'Get-FreshServiceDepartment'
    }

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $envelope = Invoke-FsuRequest @common `
            -Method GET `
            -PathSegments @('departments', [string]$Id) `
            -ResourceId ([string]$Id)
        $payload = Get-FsuSingularEnvelopePayload -Body $envelope.Body -PrimaryName 'department' -AlternateName 'departments' -CorrelationId ([string]$context.CorrelationId)
        ConvertTo-FsuDepartment -InputObject $payload
        return
    }

    $query = @{}
    if ($PSBoundParameters.ContainsKey('Name')) {
        $query['query'] = ('"name:''{0}''"' -f ($Name -replace "'", "''"))
    }

    Invoke-FsuPagedRequest @common `
        -PathSegments @('departments') `
        -QueryParameters $query `
        -EnvelopeProperty 'departments' `
        -PSTypeName 'FreshservicePSU.Department' `
        -PerPage $PerPage `
        -MaxRecords $MaxRecords |
        ConvertTo-FsuDepartment
}

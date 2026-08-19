function Get-FreshServiceAgent {
    <#
    .SYNOPSIS
        Gets one Freshservice agent or a bounded agent list.

    .DESCRIPTION
        Reads agents for PSU assignee labels, filters, and reports.
        Tenant, stage, and credentials come from the trusted PSU
        execution context. Does not deactivate, forget, convert, or
        update agents. workspace_id is not sent.

        -Id uses GET /agents/{id}. A list call uses GET /agents with
        optional email, active, or state filters. Agent data is
        cache-eligible only when it is not permission-filtered; the
        shared reference cache is not yet wired.

    .PARAMETER Id
        Freshservice agent ID.

    .PARAMETER Email
        Limit a list to this agent email.

    .PARAMETER Active
        Limit a list to active or inactive agents.

    .PARAMETER State
        Limit a list to fulltime or occasional agents.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 100.

    .PARAMETER MaxRecords
        Maximum records to emit for a list. Default 1000.

    .EXAMPLE
        Get-FreshServiceAgent -Email 'ada@contoso.com'

        Returns the matching agent for an assignee lookup.

    .OUTPUTS
        FreshservicePSU.Agent
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('FreshservicePSU.Agent')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$Id,

        [Parameter(ParameterSetName = 'List')]
        [ValidateNotNullOrEmpty()]
        [string]$Email,

        [Parameter(ParameterSetName = 'List')]
        [bool]$Active,

        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('fulltime', 'occasional')]
        [string]$State,

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
        Operation = 'Get-FreshServiceAgent'
    }

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $raw = Invoke-FsuRequest @common `
            -Method GET `
            -PathSegments @('agents', [string]$Id) `
            -EnvelopeProperty 'agent' `
            -PSTypeName 'FreshservicePSU.Agent' `
            -ResourceId ([string]$Id)
        ConvertTo-FsuAgent -InputObject $raw
        return
    }

    $query = @{}
    if ($PSBoundParameters.ContainsKey('Email')) {
        $query['email'] = $Email
    }
    if ($PSBoundParameters.ContainsKey('Active')) {
        $query['active'] = $Active.ToString().ToLowerInvariant()
    }
    if ($PSBoundParameters.ContainsKey('State')) {
        $query['state'] = $State
    }

    Invoke-FsuPagedRequest @common `
        -PathSegments @('agents') `
        -QueryParameters $query `
        -EnvelopeProperty 'agents' `
        -PSTypeName 'FreshservicePSU.Agent' `
        -PerPage $PerPage `
        -MaxRecords $MaxRecords |
        ConvertTo-FsuAgent
}

function Get-FreshServiceAgentGroup {
    <#
    .SYNOPSIS
        Gets one Freshservice agent group or a bounded group list.

    .DESCRIPTION
        Reads agent groups for PSU assignment choices and report
        dimensions. Tenant, stage, and credentials come from the trusted
        PSU execution context. Does not create, update, or change
        membership. workspace_id is not sent.

        -Id uses GET /groups/{id}. A list call uses GET /groups and
        streams pages until MaxRecords is reached. Group data is
        cache-eligible only when it is not permission-filtered; the
        shared reference cache is not yet wired.

    .PARAMETER Id
        Freshservice agent group ID.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 100.

    .PARAMETER MaxRecords
        Maximum records to emit for a list. Default 1000.

    .EXAMPLE
        Get-FreshServiceAgentGroup -Id 1

        Returns one group for an assignment form.

    .OUTPUTS
        FreshservicePSU.AgentGroup
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('FreshservicePSU.AgentGroup')]
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
        Operation = 'Get-FreshServiceAgentGroup'
    }

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $raw = Invoke-FsuRequest @common `
            -Method GET `
            -PathSegments @('groups', [string]$Id) `
            -EnvelopeProperty 'group' `
            -PSTypeName 'FreshservicePSU.AgentGroup' `
            -ResourceId ([string]$Id)
        ConvertTo-FsuAgentGroup -InputObject $raw
        return
    }

    Invoke-FsuPagedRequest @common `
        -PathSegments @('groups') `
        -EnvelopeProperty 'groups' `
        -PSTypeName 'FreshservicePSU.AgentGroup' `
        -PerPage $PerPage `
        -MaxRecords $MaxRecords |
        ConvertTo-FsuAgentGroup
}

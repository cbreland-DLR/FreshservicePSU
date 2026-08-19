function Get-FreshServiceRequestApproval {
    <#
    .SYNOPSIS
        Gets approvals belonging to one Freshservice ticket.

    .DESCRIPTION
        Reads GET /tickets/{ticket_id}/approvals[/{id}] for approval
        aging and bottleneck reports. Tenant, stage, and credentials
        come from the trusted PSU execution context. Approval actions
        are not supported. workspace_id is not sent.

    .PARAMETER TicketId
        Freshservice ticket ID.

    .PARAMETER Id
        Freshservice approval ID.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 100.

    .PARAMETER MaxRecords
        Maximum records to emit for a list. Default 1000.

    .EXAMPLE
        Get-FreshServiceRequestApproval -TicketId 20

        Returns approvals on ticket 20.

    .OUTPUTS
        FreshservicePSU.Approval
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('FreshservicePSU.Approval')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [Parameter(Mandatory, ParameterSetName = 'List')]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$TicketId,

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
        Operation = 'Get-FreshServiceRequestApproval'
        ResourceId = [string]$TicketId
    }

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $raw = Invoke-FsuRequest @common `
            -Method GET `
            -PathSegments @('tickets', [string]$TicketId, 'approvals', [string]$Id) `
            -EnvelopeProperty 'approval' `
            -PSTypeName 'FreshservicePSU.Approval'
        ConvertTo-FsuApproval -InputObject $raw -TicketId $TicketId
        return
    }

    Invoke-FsuPagedRequest @common `
        -PathSegments @('tickets', [string]$TicketId, 'approvals') `
        -EnvelopeProperty 'approvals' `
        -PSTypeName 'FreshservicePSU.Approval' `
        -PerPage $PerPage `
        -MaxRecords $MaxRecords |
        ConvertTo-FsuApproval -TicketId $TicketId
}

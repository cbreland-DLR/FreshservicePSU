function Get-FreshServiceTask {
    <#
    .SYNOPSIS
        Gets ticket tasks belonging to one Freshservice ticket.

    .DESCRIPTION
        Reads GET /tickets/{ticket_id}/tasks[/{id}] for ticket-task
        backlog and duration reports. Tenant, stage, and credentials
        come from the trusted PSU execution context. Problem, change,
        release, and project tasks are outside this command.
        workspace_id is not sent.

    .PARAMETER TicketId
        Freshservice ticket ID.

    .PARAMETER Id
        Freshservice task ID.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 100.

    .PARAMETER MaxRecords
        Maximum records to emit for a list. Default 1000.

    .EXAMPLE
        Get-FreshServiceTask -TicketId 1

        Returns tasks on ticket 1.

    .OUTPUTS
        FreshservicePSU.Task
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('FreshservicePSU.Task')]
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
        Operation = 'Get-FreshServiceTask'
        ResourceId = [string]$TicketId
    }

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $raw = Invoke-FsuRequest @common `
            -Method GET `
            -PathSegments @('tickets', [string]$TicketId, 'tasks', [string]$Id) `
            -EnvelopeProperty 'task' `
            -PSTypeName 'FreshservicePSU.Task'
        ConvertTo-FsuTask -InputObject $raw -TicketId $TicketId
        return
    }

    Invoke-FsuPagedRequest @common `
        -PathSegments @('tickets', [string]$TicketId, 'tasks') `
        -EnvelopeProperty 'tasks' `
        -PSTypeName 'FreshservicePSU.Task' `
        -PerPage $PerPage `
        -MaxRecords $MaxRecords |
        ConvertTo-FsuTask -TicketId $TicketId
}

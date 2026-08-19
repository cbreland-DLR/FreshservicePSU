function Get-FreshServiceTicketActivity {
    <#
    .SYNOPSIS
        Gets activity history for one Freshservice ticket.

    .DESCRIPTION
        Reads GET /tickets/{id}/activities using the endpoint's
        next_page_url continuation token. Tenant, stage, and credentials
        come from the trusted PSU execution context. workspace_id is
        not sent. Continuation tokens are never written to output,
        errors, or audit events.

    .PARAMETER TicketId
        Freshservice ticket ID.

    .PARAMETER MaxRecords
        Maximum activity records to emit. Default 1000.

    .EXAMPLE
        Get-FreshServiceTicketActivity -TicketId 152 -MaxRecords 60

        Streams up to 60 recent activity records for ticket 152.

    .OUTPUTS
        FreshservicePSU.TicketActivity
    #>
    [CmdletBinding()]
    [OutputType('FreshservicePSU.TicketActivity')]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$TicketId,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000
    )

    $context = Get-FsuExecutionContext
    Invoke-FsuTokenPagedRequest `
        -Context $context `
        -PathSegments @('tickets', [string]$TicketId, 'activities') `
        -EnvelopeProperty 'activities' `
        -PSTypeName 'FreshservicePSU.TicketActivity' `
        -MaxRecords $MaxRecords `
        -Operation 'Get-FreshServiceTicketActivity' `
        -ResourceId ([string]$TicketId) |
        ConvertTo-FsuTicketActivity -TicketId $TicketId
}

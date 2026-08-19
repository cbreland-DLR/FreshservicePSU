function Get-FreshServiceRequestedItem {
    <#
    .SYNOPSIS
        Gets requested items belonging to one Freshservice ticket.

    .DESCRIPTION
        Reads GET /tickets/{ticket_id}/requested_items for catalog demand
        and fulfillment reports. Tenant, stage, and credentials come from
        the trusted PSU execution context. Does not place or update a
        catalog request. workspace_id is not sent.

    .PARAMETER TicketId
        Freshservice ticket ID.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 100.

    .PARAMETER MaxRecords
        Maximum records to emit. Default 1000.

    .EXAMPLE
        Get-FreshServiceRequestedItem -TicketId 1

        Returns requested catalog items on ticket 1.

    .OUTPUTS
        FreshservicePSU.RequestedItem
    #>
    [CmdletBinding()]
    [OutputType('FreshservicePSU.RequestedItem')]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$TicketId,

        [ValidateRange(1, 100)]
        [int]$PerPage = 100,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000
    )

    $context = Get-FsuExecutionContext
    Invoke-FsuPagedRequest `
        -Context $context `
        -PathSegments @('tickets', [string]$TicketId, 'requested_items') `
        -EnvelopeProperty 'requested_items' `
        -PSTypeName 'FreshservicePSU.RequestedItem' `
        -PerPage $PerPage `
        -MaxRecords $MaxRecords `
        -Operation 'Get-FreshServiceRequestedItem' `
        -ResourceId ([string]$TicketId) |
        ConvertTo-FsuRequestedItem -TicketId $TicketId
}

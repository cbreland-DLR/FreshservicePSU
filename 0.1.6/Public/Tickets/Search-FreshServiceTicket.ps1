function Search-FreshServiceTicket {
    <#
    .SYNOPSIS
        Searches Freshservice tickets with a validated filter query.

    .DESCRIPTION
        Executes GET /tickets/filter for PSU reports and visualizations.
        Tenant, stage, and credentials come from the trusted PSU execution
        context. Bounded unfiltered lists use Get-FreshServiceTicket.

        The query is the vendor filter expression, for example
        priority:4 OR status:2. It is validated, wrapped in the required
        double quotes, and rejected when empty, longer than 512 characters,
        unbounded, malformed, or when it selects workspace_id.

        Results stream by page number (the filter endpoint documents page
        and total, not Link). Default page size is 30.

    .PARAMETER Query
        Freshservice ticket filter expression without surrounding
        double quotes.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 30, matching the filter endpoint.

    .PARAMETER MaxRecords
        Maximum records to emit. Default 1000.

    .EXAMPLE
        Search-FreshServiceTicket -Query "priority:4 OR priority:3" -MaxRecords 100

        Streams urgent and high-priority tickets for a report.

    .EXAMPLE
        Search-FreshServiceTicket -Query "status:2 AND group_id:11"

        Streams open tickets in group 11.

    .OUTPUTS
        FreshservicePSU.Ticket
    #>
    [CmdletBinding()]
    [OutputType('FreshservicePSU.Ticket')]
    param(
        [Parameter(Mandatory)]
        [string]$Query,

        [ValidateRange(1, 100)]
        [int]$PerPage = 30,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000
    )

    # Generated up front so filter-validation errors carry the same
    # CorrelationId as the rest of this invocation, without forcing
    # Get-FsuExecutionContext (and credential resolution) to run just to
    # correlate a cheap, local query-format check.
    $correlationId = [guid]::NewGuid().ToString('D')
    $normalizedQuery = Test-FsuTicketFilterQuery -Query $Query -CorrelationId $correlationId
    $context = Get-FsuExecutionContext -CorrelationId $correlationId

    Invoke-FsuNumberedPagedRequest `
        -Context $context `
        -PathSegments @('tickets', 'filter') `
        -QueryParameters @{ query = ('"{0}"' -f $normalizedQuery) } `
        -EnvelopeProperty 'tickets' `
        -PSTypeName 'FreshservicePSU.Ticket' `
        -PerPage $PerPage `
        -MaxRecords $MaxRecords `
        -Operation 'Search-FreshServiceTicket' |
        ConvertTo-FsuTicket
}

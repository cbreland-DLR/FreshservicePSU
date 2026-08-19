function Get-FreshServiceTicket {
    <#
    .SYNOPSIS
        Gets one Freshservice ticket or a bounded ticket list.

    .DESCRIPTION
        Reads tickets for PSU detail pages, bounded lists, and reports.
        Tenant, stage, and credentials come from the trusted PSU execution
        context. Filtered search uses Search-FreshServiceTicket, not this
        command.

        -TicketId uses GET /tickets/{id}. A list call uses GET /tickets
        with optional requester, email, updated-since, or predefined
        filter, and streams pages until MaxRecords is reached.

        -Include accepts only Requester, Stats, and Conversations.
        Conversations is valid only with -TicketId. Each embed adds API
        credits: +1 on a single-ticket read, +2 on a list read.

    .PARAMETER TicketId
        Freshservice ticket ID.

    .PARAMETER RequesterId
        Limit a list to one requester ID.

    .PARAMETER Email
        Limit a list to the requester email.

    .PARAMETER UpdatedSince
        Limit a list to tickets with activity at or after this time.

    .PARAMETER Filter
        Predefined list filter: new_and_my_open, watching, spam, or deleted.

    .PARAMETER Include
        Opt-in embeds: Requester, Stats, Conversations.

    .PARAMETER PerPage
        Page size from 1 to 100. Default 100.

    .PARAMETER MaxRecords
        Maximum records to emit for a list. Default 1000.

    .EXAMPLE
        Get-FreshServiceTicket -TicketId 266

        Returns one ticket for a PSU detail page.

    .EXAMPLE
        Get-FreshServiceTicket -TicketId 266 -Include Requester, Stats

        Returns one ticket with requester and stats embeds.

    .EXAMPLE
        Get-FreshServiceTicket -UpdatedSince (Get-Date).AddDays(-1) -MaxRecords 50

        Streams recent tickets for a report, stopping at 50 records.

    .OUTPUTS
        FreshservicePSU.Ticket
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('FreshservicePSU.Ticket')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$TicketId,

        [Parameter(ParameterSetName = 'List')]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$RequesterId,

        [Parameter(ParameterSetName = 'List')]
        [ValidateNotNullOrEmpty()]
        [string]$Email,

        [Parameter(ParameterSetName = 'List')]
        [datetime]$UpdatedSince,

        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('new_and_my_open', 'watching', 'spam', 'deleted')]
        [string]$Filter,

        [Parameter(ParameterSetName = 'ById')]
        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('Requester', 'Stats', 'Conversations')]
        [string[]]$Include,

        [Parameter(ParameterSetName = 'List')]
        [ValidateRange(1, 100)]
        [int]$PerPage = 100,

        [Parameter(ParameterSetName = 'List')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000
    )

    if ($PSCmdlet.ParameterSetName -eq 'List' -and @($Include) -contains 'Conversations') {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Ticket.ConversationsEmbedNotOnList' -Message 'The Conversations embed is only valid with -TicketId.' -Category InvalidArgument)
    }

    $context = Get-FsuExecutionContext
    $embedQuery = ConvertTo-FsuEmbedQuery -Include $Include

    $common = @{
        Context = $context
        Operation = 'Get-FreshServiceTicket'
    }

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $query = @{}
        if ($embedQuery) {
            $query['include'] = $embedQuery
        }

        $raw = Invoke-FsuRequest @common `
            -Method GET `
            -PathSegments @('tickets', [string]$TicketId) `
            -QueryParameters $query `
            -EnvelopeProperty 'ticket' `
            -PSTypeName 'FreshservicePSU.Ticket' `
            -ResourceId ([string]$TicketId)
        ConvertTo-FsuTicket -InputObject $raw
        return
    }

    $query = @{}
    if ($PSBoundParameters.ContainsKey('RequesterId')) {
        $query['requester_id'] = $RequesterId
    }
    if ($PSBoundParameters.ContainsKey('Email')) {
        $query['email'] = $Email
    }
    if ($PSBoundParameters.ContainsKey('UpdatedSince')) {
        $utc = if ($UpdatedSince.Kind -eq [System.DateTimeKind]::Utc) {
            $UpdatedSince
        } else {
            $UpdatedSince.ToUniversalTime()
        }
        $query['updated_since'] = $utc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($PSBoundParameters.ContainsKey('Filter')) {
        $query['filter'] = $Filter
    }
    if ($embedQuery) {
        $query['include'] = $embedQuery
    }

    Invoke-FsuPagedRequest @common `
        -PathSegments @('tickets') `
        -QueryParameters $query `
        -EnvelopeProperty 'tickets' `
        -PSTypeName 'FreshservicePSU.Ticket' `
        -PerPage $PerPage `
        -MaxRecords $MaxRecords |
        ConvertTo-FsuTicket
}

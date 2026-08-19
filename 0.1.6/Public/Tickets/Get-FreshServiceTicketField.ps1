function Get-FreshServiceTicketField {
    <#
    .SYNOPSIS
        Gets Freshservice ticket form field definitions.

    .DESCRIPTION
        Reads GET /ticket_form_fields for PSU dynamic forms and for
        resolving stored field values to display labels. Tenant, stage,
        and credentials come from the trusted PSU execution context.
        workspace_id is not sent.

        The vendor exposes a list endpoint only. -Id and -Name select one
        field from that list. Ticket-field data is cache-eligible; the
        shared reference cache is not yet wired.

    .PARAMETER Id
        Freshservice ticket field ID.

    .PARAMETER Name
        API field name, for example requester or status.

    .PARAMETER MaxRecords
        Maximum fields to emit for a full list. Default 1000.

    .EXAMPLE
        Get-FreshServiceTicketField

        Returns ticket field definitions for a PSU create-ticket form.

    .EXAMPLE
        Get-FreshServiceTicketField -Name status

        Returns the status field, including its choices.

    .OUTPUTS
        FreshservicePSU.TicketField
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType('FreshservicePSU.TicketField')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(ParameterSetName = 'List')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000
    )

    $context = Get-FsuExecutionContext
    $correlationId = [string]$context.CorrelationId

    $fields = @(
        Invoke-FsuPagedRequest `
            -Context $context `
            -PathSegments @('ticket_form_fields') `
            -EnvelopeProperty 'ticket_fields' `
            -PSTypeName 'FreshservicePSU.TicketField' `
            -PerPage 100 `
            -MaxRecords 1000 `
            -Operation 'Get-FreshServiceTicketField' |
            ConvertTo-FsuTicketField
    )

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $match = @($fields | Where-Object { [string]$_.Id -eq [string]$Id })
        if ($match.Count -eq 0) {
            throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.TicketField.NotFound' -Message 'The requested ticket field was not found.' -Category ObjectNotFound -CorrelationId $correlationId)
        }
        $match[0]
        return
    }

    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $match = @($fields | Where-Object { [string]::Equals([string]$_.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($match.Count -eq 0) {
            throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.TicketField.NotFound' -Message 'The requested ticket field was not found.' -Category ObjectNotFound -CorrelationId $correlationId)
        }
        $match[0]
        return
    }

    $emitted = 0
    foreach ($field in $fields) {
        if ($emitted -ge $MaxRecords) {
            return
        }
        $field
        $emitted++
    }
}

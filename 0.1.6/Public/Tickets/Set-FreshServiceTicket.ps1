function Set-FreshServiceTicket {
    <#
    .SYNOPSIS
        Updates ordinary properties on one Freshservice ticket.

    .DESCRIPTION
        Sends PUT /tickets/{id} with only the caller-supplied fields.
        Tenant, stage, and credentials come from the trusted PSU
        execution context. Supports ShouldProcess and -WhatIf. Closing
        a ticket is an ordinary Status update. workspace_id is not
        sent. Restore, deletion, and workspace moves are out of scope.

        CustomFields are validated against Get-FreshServiceTicketField
        before the request is sent, including under -WhatIf (validation is
        a read-only call and runs ahead of the ShouldProcess prompt).

    .PARAMETER TicketId
        Freshservice ticket ID.

    .PARAMETER Subject
        Replacement subject.

    .PARAMETER Description
        Replacement description. Bind as $null to send JSON null. Accepts
        $null or a string; any other type is rejected.

    .PARAMETER RequesterId
        Replacement requester ID.

    .PARAMETER Status
        Ticket status number. Closed is 5.

    .PARAMETER Priority
        Ticket priority number.

    .PARAMETER Type
        Ticket type.

    .PARAMETER Source
        Channel number.

    .PARAMETER Urgency
        Ticket urgency number.

    .PARAMETER Impact
        Ticket impact number.

    .PARAMETER GroupId
        Assigned group ID, or $null to clear.

    .PARAMETER AgentId
        Assigned agent ID (responder_id), or $null to clear.

    .PARAMETER Category
        Ticket category.

    .PARAMETER SubCategory
        Ticket subcategory.

    .PARAMETER ItemCategory
        Ticket item category.

    .PARAMETER Tags
        Replacement tag list.

    .PARAMETER DepartmentId
        Department ID, or $null to clear.

    .PARAMETER AssetDisplayId
        Asset display ID to associate.

    .PARAMETER DueBy
        Resolution due timestamp.

    .PARAMETER FirstResponseDueBy
        First-response due timestamp.

    .PARAMETER CustomFields
        Custom field name/value pairs. Names must exist on
        Get-FreshServiceTicketField.

    .EXAMPLE
        Set-FreshServiceTicket -TicketId 265 -Status 5 -WhatIf

        Shows the close that would be sent without calling Freshservice.

    .OUTPUTS
        FreshservicePSU.Ticket
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('FreshservicePSU.Ticket')]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$TicketId,

        [ValidateNotNullOrEmpty()]
        [string]$Subject,

        # [object], not [string]: PowerShell converts a bound $null to ''
        # for a [string] parameter, which silently breaks the "bind as
        # $null to send JSON null" contract shared with Set-FreshServiceAsset.
        # [object] lets $null bind as $null; the type is validated
        # explicitly below and a bound string is normalized to [string]
        # before use.
        [AllowNull()]
        [object]$Description,

        [ValidateRange(1, [long]::MaxValue)]
        [long]$RequesterId,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$Status,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$Priority,

        [ValidateNotNullOrEmpty()]
        [string]$Type,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$Source,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$Urgency,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$Impact,

        [AllowNull()]
        [Nullable[long]]$GroupId,

        [AllowNull()]
        [Nullable[long]]$AgentId,

        [ValidateNotNullOrEmpty()]
        [string]$Category,

        [ValidateNotNullOrEmpty()]
        [string]$SubCategory,

        [ValidateNotNullOrEmpty()]
        [string]$ItemCategory,

        [string[]]$Tags,

        [AllowNull()]
        [Nullable[long]]$DepartmentId,

        [ValidateRange(1, [long]::MaxValue)]
        [long]$AssetDisplayId,

        [datetime]$DueBy,

        [datetime]$FirstResponseDueBy,

        [System.Collections.IDictionary]$CustomFields
    )

    if ($PSBoundParameters.ContainsKey('Description') -and $null -ne $Description -and $Description -isnot [string]) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Ticket.InvalidDescription' -Message 'Description must be a string or $null.' -Category InvalidArgument)
    }

    $write = ConvertTo-FsuTicketWriteBody -BoundParameters $PSBoundParameters -Exclude @('TicketId')
    if ($write.BoundVendorNames.Count -eq 0) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Ticket.NoUpdateFields' -Message 'At least one updatable ticket property must be supplied.' -Category InvalidArgument)
    }

    # Validated ahead of ShouldProcess so -WhatIf catches an unknown custom
    # field name too, matching this command's documented promise that
    # CustomFields are validated before the request is sent. No context
    # exists yet to correlate this call; Get-FreshServiceTicketField builds
    # its own.
    if ($PSBoundParameters.ContainsKey('CustomFields')) {
        Test-FsuTicketCustomField -CustomFields $CustomFields
    }

    if (-not $PSCmdlet.ShouldProcess("ticket ID $TicketId", 'Update')) {
        return
    }

    $context = Get-FsuExecutionContext
    $raw = Invoke-FsuRequest `
        -Context $context `
        -Method PUT `
        -PathSegments @('tickets', [string]$TicketId) `
        -Body $write.Body `
        -BoundParameterNames $write.BoundVendorNames `
        -EnvelopeProperty 'ticket' `
        -PSTypeName 'FreshservicePSU.Ticket' `
        -Operation 'Set-FreshServiceTicket' `
        -ResourceId ([string]$TicketId)
    ConvertTo-FsuTicket -InputObject $raw
}

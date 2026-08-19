function New-FreshServiceTicket {
    <#
    .SYNOPSIS
        Creates one Freshservice ticket.

    .DESCRIPTION
        Sends POST /tickets with only the caller-supplied fields.
        Tenant, stage, and credentials come from the trusted PSU
        execution context. Supports ShouldProcess and -WhatIf.
        Requires a requester identity (ID or email), subject, and
        description. workspace_id is not sent. Attachments, replies,
        and email_config_id are out of scope.

        CustomFields are validated against Get-FreshServiceTicketField
        before the request is sent, including under -WhatIf (validation is
        a read-only call and runs ahead of the ShouldProcess prompt). POST
        is not retried after an uncertain delivery.

    .PARAMETER RequesterId
        Existing Freshservice requester ID.

    .PARAMETER Email
        Requester email. Creates a contact if none exists.

    .PARAMETER Subject
        Ticket subject.

    .PARAMETER Description
        Ticket description.

    .PARAMETER Status
        Ticket status number. Open is 2.

    .PARAMETER Priority
        Ticket priority number. Low is 1.

    .PARAMETER Type
        Ticket type, for example Incident.

    .PARAMETER Source
        Channel number. Portal is 2.

    .PARAMETER Urgency
        Ticket urgency number.

    .PARAMETER Impact
        Ticket impact number.

    .PARAMETER GroupId
        Assigned group ID.

    .PARAMETER AgentId
        Assigned agent ID (responder_id).

    .PARAMETER Category
        Ticket category.

    .PARAMETER SubCategory
        Ticket subcategory.

    .PARAMETER ItemCategory
        Ticket item category.

    .PARAMETER Tags
        Tags to associate with the ticket.

    .PARAMETER DepartmentId
        Department ID.

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
        New-FreshServiceTicket -Email 'ada@contoso.com' -Subject 'VPN' -Description 'Cannot connect' -WhatIf

        Shows the create that would be sent without calling Freshservice.

    .OUTPUTS
        FreshservicePSU.Ticket
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByEmail')]
    [OutputType('FreshservicePSU.Ticket')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByRequesterId')]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$RequesterId,

        [Parameter(Mandatory, ParameterSetName = 'ByEmail')]
        [ValidateNotNullOrEmpty()]
        [string]$Email,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Subject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Description,

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

        [ValidateRange(1, [long]::MaxValue)]
        [long]$GroupId,

        [ValidateRange(1, [long]::MaxValue)]
        [long]$AgentId,

        [ValidateNotNullOrEmpty()]
        [string]$Category,

        [ValidateNotNullOrEmpty()]
        [string]$SubCategory,

        [ValidateNotNullOrEmpty()]
        [string]$ItemCategory,

        [string[]]$Tags,

        [ValidateRange(1, [long]::MaxValue)]
        [long]$DepartmentId,

        [ValidateRange(1, [long]::MaxValue)]
        [long]$AssetDisplayId,

        [datetime]$DueBy,

        [datetime]$FirstResponseDueBy,

        [System.Collections.IDictionary]$CustomFields
    )

    $write = ConvertTo-FsuTicketWriteBody -BoundParameters $PSBoundParameters
    # Validated ahead of ShouldProcess so -WhatIf catches an unknown custom
    # field name too, matching this command's documented promise that
    # CustomFields are validated before the request is sent. No context
    # exists yet to correlate this call; Get-FreshServiceTicketField builds
    # its own.
    if ($PSBoundParameters.ContainsKey('CustomFields')) {
        Test-FsuTicketCustomField -CustomFields $CustomFields
    }
    if (-not $PSCmdlet.ShouldProcess($Subject, 'Create ticket')) {
        return
    }

    $context = Get-FsuExecutionContext
    $raw = Invoke-FsuRequest `
        -Context $context `
        -Method POST `
        -PathSegments @('tickets') `
        -Body $write.Body `
        -BoundParameterNames $write.BoundVendorNames `
        -EnvelopeProperty 'ticket' `
        -PSTypeName 'FreshservicePSU.Ticket' `
        -Operation 'New-FreshServiceTicket'
    ConvertTo-FsuTicket -InputObject $raw
}
